//! Application-owned admission for descriptor and playlist dependencies.
//!
//! Format parsers may report the references present in a descriptor, but they
//! do not have authority to turn those references into source rows. This
//! module performs that bounded admission against the committed source graph
//! supplied by the caller. The provider still owns opening the resulting
//! opaque locators and reading their bytes.

use std::path::{Component, Path};

use crate::{RelativeSourceLocator, SourceEntryKind, SourceEntryRecord};

/// Maximum number of source members admitted for one descriptor or playlist.
pub const MAX_OPTICAL_DEPENDENCIES: usize = 128;

/// A descriptor or playlist reference could not be admitted from the source
/// graph.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum OpticalDependencyError {
    /// The reference is empty, absolute, malformed, or contains traversal.
    InvalidReference,
    /// Traversal attempted to leave the configured root.
    CrossRoot,
    /// No committed source entry matches the normalized reference.
    Missing,
    /// More than one committed source entry matches the reference.
    Ambiguous,
    /// The same source entry was referenced more than once.
    Duplicate,
    /// The reference list exceeds the bounded admission limit.
    ResourceLimitExceeded,
}

/// One already-committed source entry paired with a caller-owned, normalized
/// reference inside the current optical scope.
///
/// The reference is deliberately separate from the source-entry coordinate.
/// Derived-container callers can provide a safe member path without exposing
/// or parsing their transformation-owned locator.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ContentDependencyCandidate {
    source: SourceEntryRecord,
    scope_reference: String,
}

impl ContentDependencyCandidate {
    /// Creates a candidate for one normalized scope reference.
    pub fn new(source: SourceEntryRecord, scope_reference: impl Into<String>) -> Self {
        Self {
            source,
            scope_reference: scope_reference.into(),
        }
    }

    /// Returns the committed source entry.
    pub fn source(&self) -> &SourceEntryRecord {
        &self.source
    }

    /// Returns the caller-owned scope reference.
    pub fn scope_reference(&self) -> &str {
        &self.scope_reference
    }
}

trait DependencyCandidate {
    fn source(&self) -> &SourceEntryRecord;

    fn matches_normalized_reference(&self, normalized: &str) -> bool;
}

impl DependencyCandidate for SourceEntryRecord {
    fn source(&self) -> &SourceEntryRecord {
        self
    }

    fn matches_normalized_reference(&self, normalized: &str) -> bool {
        self.kind() == SourceEntryKind::File
            && self
                .relative_locator()
                .and_then(|locator| normalize_relative(locator.as_provider_value()))
                .as_deref()
                == Some(normalized)
    }
}

impl DependencyCandidate for ContentDependencyCandidate {
    fn source(&self) -> &SourceEntryRecord {
        &self.source
    }

    fn matches_normalized_reference(&self, normalized: &str) -> bool {
        self.source.kind() == SourceEntryKind::File
            && normalize_scope_reference(self.scope_reference()).as_deref() == Some(normalized)
    }
}

/// Resolves descriptor or playlist references against one committed scan.
///
/// The candidates must already be restricted by the caller to the same
/// configured root and scan checkpoint as the descriptor or playlist. The
/// resolver never walks the filesystem and never treats a filename as identity
/// evidence; it only maps a parser-reported locator to an existing source row.
pub fn resolve_optical_dependencies(
    descriptor_locator: &RelativeSourceLocator,
    references: &[String],
    candidates: &[SourceEntryRecord],
) -> Result<Vec<SourceEntryRecord>, OpticalDependencyError> {
    validate_reference_count(references)?;
    let descriptor = normalize_relative(descriptor_locator.as_provider_value())
        .ok_or(OpticalDependencyError::InvalidReference)?;
    resolve_dependencies(&descriptor, references, candidates)
}

/// Resolves descriptor or playlist references against provider-neutral scope
/// candidates.
///
/// This is the derived-source counterpart to
/// [`resolve_optical_dependencies`]. The caller supplies safe scope
/// references from its transformation-owned member index. This function only
/// normalizes those references and never interprets a provider or derived
/// locator token.
pub fn resolve_content_dependencies(
    descriptor_reference: &str,
    references: &[String],
    candidates: &[ContentDependencyCandidate],
) -> Result<Vec<SourceEntryRecord>, OpticalDependencyError> {
    validate_reference_count(references)?;
    let descriptor = normalize_scope_reference(descriptor_reference)
        .ok_or(OpticalDependencyError::InvalidReference)?;
    resolve_dependencies(&descriptor, references, candidates)
}

fn validate_reference_count(references: &[String]) -> Result<(), OpticalDependencyError> {
    if references.is_empty() {
        return Err(OpticalDependencyError::Missing);
    }
    if references.len() > MAX_OPTICAL_DEPENDENCIES {
        return Err(OpticalDependencyError::ResourceLimitExceeded);
    }
    Ok(())
}

fn resolve_dependencies<C: DependencyCandidate>(
    descriptor: &str,
    references: &[String],
    candidates: &[C],
) -> Result<Vec<SourceEntryRecord>, OpticalDependencyError> {
    let parent = descriptor
        .rsplit_once('/')
        .map(|(parent, _)| parent)
        .unwrap_or("");
    let mut resolved = Vec::with_capacity(references.len());

    for reference in references {
        let normalized_reference = normalize_reference(reference)?;
        let normalized = if parent.is_empty() {
            normalized_reference
        } else {
            format!("{parent}/{normalized_reference}")
        };
        let matches: Vec<&C> = candidates
            .iter()
            .filter(|candidate| candidate.matches_normalized_reference(&normalized))
            .collect();
        let entry = match matches.as_slice() {
            [] => return Err(OpticalDependencyError::Missing),
            [entry] => entry.source(),
            _ => return Err(OpticalDependencyError::Ambiguous),
        };
        if resolved.iter().any(|existing: &SourceEntryRecord| {
            existing.source_entry_id() == entry.source_entry_id()
        }) {
            return Err(OpticalDependencyError::Duplicate);
        }
        resolved.push(entry.clone());
    }
    Ok(resolved)
}

fn normalize_reference(reference: &str) -> Result<String, OpticalDependencyError> {
    if reference.trim().is_empty() {
        return Err(OpticalDependencyError::InvalidReference);
    }
    if has_drive_prefix(reference.trim()) {
        return Err(OpticalDependencyError::CrossRoot);
    }
    let path = Path::new(reference.trim());
    if path.is_absolute() {
        return Err(OpticalDependencyError::CrossRoot);
    }
    if path
        .components()
        .any(|component| matches!(component, Component::Prefix(_) | Component::RootDir))
    {
        return Err(OpticalDependencyError::CrossRoot);
    }
    if path
        .components()
        .any(|component| matches!(component, Component::ParentDir))
    {
        return Err(OpticalDependencyError::CrossRoot);
    }
    normalize_relative(reference).ok_or(OpticalDependencyError::InvalidReference)
}

fn normalize_relative(value: &str) -> Option<String> {
    let value = value.trim().replace('\\', "/");
    if value.is_empty() || value.starts_with('/') {
        return None;
    }
    let mut segments = Vec::new();
    for segment in value.split('/') {
        match segment {
            "" | "." => {}
            ".." => return None,
            segment if segment.contains('\0') => return None,
            segment => segments.push(segment),
        }
    }
    (!segments.is_empty()).then(|| segments.join("/"))
}

fn normalize_scope_reference(value: &str) -> Option<String> {
    let value = value.trim();
    if value.starts_with(['/', '\\']) {
        return None;
    }
    if has_drive_prefix(value) {
        return None;
    }
    normalize_relative(value)
}

fn has_drive_prefix(value: &str) -> bool {
    let bytes = value.as_bytes();
    bytes.len() >= 2 && bytes[0].is_ascii_alphabetic() && bytes[1] == b':'
}
