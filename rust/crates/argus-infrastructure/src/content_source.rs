//! Reopening of provider-native and transformation-derived content.
//!
//! A resolver reconstructs the current bytes for a persisted source entry by
//! replaying its parent transformation chain. Staged files are deliberately
//! absent from this API: every open starts at the current provider source and
//! creates only operation-scoped readers.

use std::collections::HashSet;

use argus_application::{
    DerivedScopeOutcome, LibrarySourceAccess, SourceAccessError, SourceEntryCoordinates,
    SourceEntryKind, SourceEntryRecord, SourceVersionEvidence, TransformationFailure,
};

use super::content_archive::enumerate_derived_container;
use super::content_session::ParsingSession;
use super::content_stream::{ContentReadError, ContentReader};

/// Reopens one persisted source entry from the current provider bytes.
///
/// The resolver receives the bounded source-entry projection already loaded
/// by the application. It never parses provider locators or derived locators;
/// provider access and the owning transformation decoder retain those duties.
pub struct ContentSourceResolver<'a> {
    access: &'a dyn LibrarySourceAccess,
    root: &'a argus_application::ResolvedRoot,
    entries: &'a [SourceEntryRecord],
}

impl<'a> ContentSourceResolver<'a> {
    /// Creates a resolver for one provider root and its persisted source graph.
    pub fn new(
        access: &'a dyn LibrarySourceAccess,
        root: &'a argus_application::ResolvedRoot,
        entries: &'a [SourceEntryRecord],
    ) -> Self {
        Self {
            access,
            root,
            entries,
        }
    }

    /// Opens the current bytes represented by one source-entry record.
    ///
    /// Provider-native bytes are returned through the provider's bounded
    /// positional-read handle. Derived bytes are rebuilt from the nearest
    /// provider ancestor, with every persisted key, locator, transformation
    /// revision, and derived fingerprint checked against fresh enumeration.
    pub fn open(
        &self,
        entry: &SourceEntryRecord,
        session: &mut ParsingSession<'_>,
    ) -> Result<Box<dyn ContentReader>, TransformationFailure> {
        session.check_cancelled()?;
        let chain = self.parent_chain(entry)?;
        let provider = chain.first().ok_or(TransformationFailure::Malformed)?;
        if provider.kind() != SourceEntryKind::File {
            return Err(TransformationFailure::UnsupportedFeature);
        }

        let mut reader = self.open_provider(provider)?;
        let mut parent_version = provider_version(provider);
        let mut entered_scopes = 0_u32;
        let result = (|| {
            for child in chain.iter().skip(1) {
                session.enter_container()?;
                entered_scopes = entered_scopes.saturating_add(1);

                let scope_result =
                    enumerate_derived_container(&mut *reader, &parent_version, session);
                let scope = match scope_result {
                    Ok(Some(scope)) => scope,
                    Ok(None) => return Err(TransformationFailure::SourceChanged),
                    Err(error) => return Err(error),
                };
                if scope.outcome() != DerivedScopeOutcome::Complete
                    || scope.transformation_id() != child.transformation_id()
                    || scope.transformation_revision() != child.transformation_revision()
                {
                    return Err(TransformationFailure::SourceChanged);
                }
                if !reader
                    .source_version_is_unchanged()
                    .map_err(|_| TransformationFailure::ReadFailure)?
                {
                    return Err(TransformationFailure::SourceChanged);
                }

                let key = child
                    .derived_entry_key()
                    .ok_or(TransformationFailure::Malformed)?;
                let observation = scope
                    .observations()
                    .iter()
                    .find(|observation| observation.derived_entry_key() == key)
                    .ok_or(TransformationFailure::SourceChanged)?;
                if child.derived_locator() != Some(observation.derived_locator())
                    || child.derived_fingerprint() != Some(observation.derived_fingerprint())
                {
                    return Err(TransformationFailure::SourceChanged);
                }
                if observation.kind() != SourceEntryKind::File {
                    return Err(TransformationFailure::UnsupportedFeature);
                }
                let length = scope
                    .member_index()
                    .member_len(key)
                    .ok_or(TransformationFailure::SourceChanged)?;
                let file = scope
                    .member_index()
                    .open(key)
                    .map_err(|_| TransformationFailure::SourceChanged)?;
                reader = Box::new(StagedContentReader::new(file, length));
                parent_version = SourceVersionEvidence::derived(
                    child.source_entry_id(),
                    observation.derived_fingerprint().clone(),
                    child.last_observed_scan_id(),
                );
            }
            session.check_cancelled()?;
            Ok(reader)
        })();
        for _ in 0..entered_scopes {
            session.leave_container();
        }
        result
    }

    fn parent_chain(
        &self,
        entry: &SourceEntryRecord,
    ) -> Result<Vec<SourceEntryRecord>, TransformationFailure> {
        let mut chain = vec![entry.clone()];
        let mut seen = HashSet::new();
        seen.insert(entry.source_entry_id());

        while matches!(
            chain
                .last()
                .ok_or(TransformationFailure::Malformed)?
                .coordinates(),
            SourceEntryCoordinates::Derived { .. }
        ) {
            let current = chain.last().ok_or(TransformationFailure::Malformed)?;
            let parent_id = current
                .parent_source_entry_id()
                .ok_or(TransformationFailure::Malformed)?;
            if !seen.insert(parent_id) {
                return Err(TransformationFailure::Malformed);
            }
            let parent = self
                .entries
                .iter()
                .find(|candidate| candidate.source_entry_id() == parent_id)
                .cloned()
                .ok_or(TransformationFailure::SourceChanged)?;
            chain.push(parent);
        }

        chain.reverse();
        if !matches!(
            chain.first().map(SourceEntryRecord::coordinates),
            Some(SourceEntryCoordinates::Provider { .. })
        ) {
            return Err(TransformationFailure::Malformed);
        }
        Ok(chain)
    }

    fn open_provider(
        &self,
        entry: &SourceEntryRecord,
    ) -> Result<Box<dyn ContentReader>, TransformationFailure> {
        let relative = entry
            .relative_locator()
            .ok_or(TransformationFailure::Malformed)?;
        let source = self
            .access
            .open_entry_read(self.root, relative)
            .map_err(map_source_error)?;
        let reader = ProviderContentReader::new(source);
        if let (Some(expected), Some(actual)) =
            (entry.source_fingerprint(), reader.source_fingerprint())
            && expected != actual
        {
            return Err(TransformationFailure::SourceChanged);
        }
        Ok(Box::new(reader))
    }
}

fn map_source_error(error: SourceAccessError) -> TransformationFailure {
    match error {
        SourceAccessError::Cancelled => TransformationFailure::Cancelled,
        SourceAccessError::InvalidResponse => TransformationFailure::Malformed,
        _ => TransformationFailure::ReadFailure,
    }
}

fn provider_version(entry: &SourceEntryRecord) -> SourceVersionEvidence {
    SourceVersionEvidence::provider(
        entry.source_entry_id(),
        entry.source_fingerprint().map(str::to_owned),
        entry.last_observed_scan_id(),
    )
}

struct ProviderContentReader {
    source: Box<dyn argus_application::SourceReadHandle>,
}

impl ProviderContentReader {
    fn new(source: Box<dyn argus_application::SourceReadHandle>) -> Self {
        Self { source }
    }
}

impl ContentReader for ProviderContentReader {
    fn len(&self) -> Result<u64, ContentReadError> {
        self.source.len().map_err(|_| ContentReadError::Io)
    }

    fn read_at(&mut self, offset: u64, destination: &mut [u8]) -> Result<usize, ContentReadError> {
        if destination.len() > self.max_read_size() {
            return Err(ContentReadError::RequestTooLarge);
        }
        let end = offset
            .checked_add(destination.len() as u64)
            .ok_or(ContentReadError::OutOfRange)?;
        if end > self.len()? {
            return Err(ContentReadError::OutOfRange);
        }
        let count = self
            .source
            .read_at(offset, destination)
            .map_err(|_| ContentReadError::Io)?;
        if count > destination.len() {
            return Err(ContentReadError::Io);
        }
        Ok(count)
    }

    fn max_read_size(&self) -> usize {
        self.source.max_read_size()
    }

    fn source_fingerprint(&self) -> Option<&str> {
        self.source.source_fingerprint()
    }

    fn source_version_is_unchanged(&self) -> Result<bool, ContentReadError> {
        self.source
            .source_version_is_unchanged()
            .map_err(|_| ContentReadError::Io)
    }
}

struct StagedContentReader {
    file: std::fs::File,
    length: u64,
}

impl StagedContentReader {
    fn new(file: std::fs::File, length: u64) -> Self {
        Self { file, length }
    }
}

impl ContentReader for StagedContentReader {
    fn len(&self) -> Result<u64, ContentReadError> {
        Ok(self.length)
    }

    fn read_at(&mut self, offset: u64, destination: &mut [u8]) -> Result<usize, ContentReadError> {
        if destination.len() > self.max_read_size() {
            return Err(ContentReadError::RequestTooLarge);
        }
        let end = offset
            .checked_add(destination.len() as u64)
            .ok_or(ContentReadError::OutOfRange)?;
        if end > self.length {
            return Err(ContentReadError::OutOfRange);
        }
        use std::io::{Read, Seek, SeekFrom};
        self.file
            .seek(SeekFrom::Start(offset))
            .map_err(|_| ContentReadError::Io)?;
        self.file
            .read_exact(destination)
            .map_err(|_| ContentReadError::Io)?;
        Ok(destination.len())
    }
}
