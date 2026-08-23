//! Application-owned logical-content identity and grouping contracts.

use argus_domain::{ContentType, GameContentId, GameId, PlatformId};

use crate::{
    ApplicationError, ErrorCode, LogicalLibraryQueries, OperationContext, PersistenceError,
    SafeContext, ScanRunId, SourceEntryId, TraceId,
};

/// Current identity and exact source evidence produced outside a write transaction.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ContentIdentity {
    scheme_id: String,
    revision: u32,
    digest: crate::IdentityDigest,
}

impl ContentIdentity {
    /// Creates one immutable identity value.
    pub fn new(scheme_id: impl Into<String>, revision: u32, digest: crate::IdentityDigest) -> Self {
        Self {
            scheme_id: scheme_id.into(),
            revision,
            digest,
        }
    }

    /// Returns the stable scheme identifier.
    pub fn scheme_id(&self) -> &str {
        &self.scheme_id
    }

    /// Returns the scheme revision.
    pub const fn revision(&self) -> u32 {
        self.revision
    }

    /// Returns the fixed-width digest.
    pub const fn digest(&self) -> crate::IdentityDigest {
        self.digest
    }
}

/// Persisted source-version evidence captured by the out-of-transaction read.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SourceVersionEvidence {
    source_entry_id: SourceEntryId,
    source_fingerprint: Option<String>,
    last_observed_scan_id: ScanRunId,
}

impl SourceVersionEvidence {
    /// Creates an immutable source-version snapshot.
    pub fn new(
        source_entry_id: SourceEntryId,
        source_fingerprint: Option<String>,
        last_observed_scan_id: ScanRunId,
    ) -> Self {
        Self {
            source_entry_id,
            source_fingerprint,
            last_observed_scan_id,
        }
    }

    /// Returns the source identity.
    pub const fn source_entry_id(&self) -> SourceEntryId {
        self.source_entry_id
    }

    /// Returns the cheap persisted fingerprint, if available.
    pub fn source_fingerprint(&self) -> Option<&str> {
        self.source_fingerprint.as_deref()
    }

    /// Returns the scan observation version.
    pub const fn last_observed_scan_id(&self) -> ScanRunId {
        self.last_observed_scan_id
    }
}

/// One fully validated identity derivation ready for short persistence work.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ValidatedContentDerivation {
    source_entry_id: SourceEntryId,
    source_version: SourceVersionEvidence,
    platform: PlatformId,
    content_type: ContentType,
    identity: ContentIdentity,
    association_key: String,
    fallback_title: String,
}

impl ValidatedContentDerivation {
    /// Creates a derivation. Source I/O and all expensive representation work
    /// must already be complete before this value is constructed.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        source_entry_id: SourceEntryId,
        source_version: SourceVersionEvidence,
        platform: PlatformId,
        content_type: ContentType,
        identity: ContentIdentity,
        association_key: String,
        fallback_title: String,
    ) -> Self {
        Self {
            source_entry_id,
            source_version,
            platform,
            content_type,
            identity,
            association_key,
            fallback_title,
        }
    }

    /// Returns the source being identified.
    pub const fn source_entry_id(&self) -> SourceEntryId {
        self.source_entry_id
    }

    /// Returns the persisted version evidence to compare in the UoW.
    pub fn source_version(&self) -> &SourceVersionEvidence {
        &self.source_version
    }

    /// Returns the recognized platform.
    pub const fn platform(&self) -> PlatformId {
        self.platform
    }

    /// Returns the recognized content type.
    pub const fn content_type(&self) -> ContentType {
        self.content_type
    }

    /// Returns the selected current identity.
    pub fn identity(&self) -> &ContentIdentity {
        &self.identity
    }

    /// Returns the deterministic association discriminator.
    pub fn association_key(&self) -> &str {
        &self.association_key
    }

    /// Returns the presentation-only local fallback title.
    pub fn fallback_title(&self) -> &str {
        &self.fallback_title
    }
}

/// Result of one atomic identity convergence operation.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ConvergenceOutcome {
    /// A new content and provisional game were created.
    Created {
        /// Newly created logical content identity.
        game_content_id: GameContentId,
        /// Newly created provisional game identity.
        game_id: GameId,
    },
    /// A duplicate attached to an existing content/game pair.
    Attached {
        /// Existing logical content identity.
        game_content_id: GameContentId,
        /// Existing canonical game identity.
        game_id: GameId,
    },
}

/// Transaction-bound persistence seam used after validation and source reads.
pub trait IdentityConvergenceStore {
    /// Compares only persisted source-version evidence with the read snapshot.
    fn source_version_matches(
        &mut self,
        evidence: &SourceVersionEvidence,
    ) -> Result<bool, PersistenceError>;

    /// Atomically converges the validated derivation into content, source,
    /// membership, game, and projection state.
    fn converge_identity(
        &mut self,
        derivation: &ValidatedContentDerivation,
    ) -> Result<ConvergenceOutcome, PersistenceError>;
}

/// Complete transaction-bound logical-content repository contract.
pub trait LogicalContentRepository: IdentityConvergenceStore + LogicalLibraryQueries {
    /// Applies final-source absence to all affected logical associations in
    /// the same transaction as source-entry removal.
    fn finalize_source_absence(
        &mut self,
        source_entry_ids: &[SourceEntryId],
    ) -> Result<u64, PersistenceError>;
}

/// Additive Unit-of-Work extension for logical-content persistence.
pub trait LogicalContentUnitOfWork {
    /// Repository type borrowing the active transaction.
    type LogicalContentRepository<'scope>: LogicalContentRepository
    where
        Self: 'scope;

    /// Returns the logical-content repository for the active transaction.
    fn logical_content(&mut self) -> Self::LogicalContentRepository<'_>;
}

/// Application orchestration for the internal identification capability.
pub struct IdentificationService;

impl IdentificationService {
    /// Performs the persistence-only source re-check and then converges.
    pub fn converge<S: IdentityConvergenceStore>(
        store: &mut S,
        derivation: ValidatedContentDerivation,
        context: OperationContext,
    ) -> Result<ConvergenceOutcome, ApplicationError> {
        let matches = store
            .source_version_matches(derivation.source_version())
            .map_err(|_| application_error(ErrorCode::InternalUnexpected, context.trace_id()))?;
        if !matches {
            return Err(application_error(
                ErrorCode::OperationSourceChangedDuringProcessing,
                context.trace_id(),
            ));
        }
        store
            .converge_identity(&derivation)
            .map_err(|_| application_error(ErrorCode::InternalUnexpected, context.trace_id()))
    }
}

fn application_error(code: ErrorCode, trace_id: TraceId) -> ApplicationError {
    ApplicationError::from_code(code, trace_id, SafeContext::new())
        .expect("logical-content error uses an allowlisted empty context")
}
