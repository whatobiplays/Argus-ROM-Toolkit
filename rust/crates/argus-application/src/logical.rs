//! Application-owned logical-content identity and grouping contracts.

use argus_domain::{ContentProvenanceRole, ContentType, GameContentId, GameId, PlatformId};

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

/// One source member in an exact identity-proof basis.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProvenanceMember {
    role: ContentProvenanceRole,
    association_key: Option<String>,
    source_version: SourceVersionEvidence,
}

impl ProvenanceMember {
    /// Creates one provenance member from a source-version snapshot.
    pub fn new(
        role: ContentProvenanceRole,
        association_key: Option<String>,
        source_version: SourceVersionEvidence,
    ) -> Self {
        Self {
            role,
            association_key,
            source_version,
        }
    }

    /// Returns the proof role assigned to this source.
    pub const fn role(&self) -> ContentProvenanceRole {
        self.role
    }

    /// Returns the optional derived-unit association discriminator.
    pub fn association_key(&self) -> Option<&str> {
        self.association_key.as_deref()
    }

    /// Returns the source-version evidence captured before persistence.
    pub fn source_version(&self) -> &SourceVersionEvidence {
        &self.source_version
    }

    /// Returns the source entry represented by this member.
    pub fn source_entry_id(&self) -> SourceEntryId {
        self.source_version.source_entry_id()
    }
}

/// Failure while constructing an exact provenance basis.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ProvenanceBasisError {
    /// An identity proof must contain at least one source member.
    Empty,
}

/// One fully validated identity derivation ready for short persistence work.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ValidatedContentDerivation {
    provenance: Vec<ProvenanceMember>,
    platform: PlatformId,
    content_type: ContentType,
    identity: ContentIdentity,
    fallback_title: String,
}

/// One already identified disc selected by an ordered M3U relationship.
///
/// The ordinal is intentionally transient grouping evidence. It is not part
/// of GameMembership and therefore cannot become an alternate membership
/// authority.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct M3uGroupingMember {
    game_content_id: GameContentId,
    source_version: SourceVersionEvidence,
    ordinal: u32,
}

impl M3uGroupingMember {
    /// Creates one ordered M3U member from its current source evidence.
    pub fn new(
        game_content_id: GameContentId,
        source_version: SourceVersionEvidence,
        ordinal: u32,
    ) -> Self {
        Self {
            game_content_id,
            source_version,
            ordinal,
        }
    }

    /// Returns the already identified logical disc.
    pub const fn game_content_id(&self) -> GameContentId {
        self.game_content_id
    }

    /// Returns the physical source version used by the relationship evidence.
    pub fn source_version(&self) -> &SourceVersionEvidence {
        &self.source_version
    }

    /// Returns the playlist position stored in grouping evidence.
    pub const fn ordinal(&self) -> u32 {
        self.ordinal
    }
}

/// Failure while constructing ordered M3U relationship evidence.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum M3uGroupingError {
    /// A playlist must contain at least one member.
    Empty,
    /// Ordinals must be contiguous and ordered from zero.
    InvalidOrdinal,
    /// A content unit or proving source may occur only once in one playlist.
    DuplicateMember,
    /// The playlist source cannot also be one of its members.
    PlaylistAppearsAsMember,
}

/// Version-bound ordered M3U relationship evidence.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ValidatedM3uGrouping {
    playlist_source_version: SourceVersionEvidence,
    members: Vec<M3uGroupingMember>,
}

impl ValidatedM3uGrouping {
    /// Creates relationship evidence after validating its non-empty order.
    pub fn new(
        playlist_source_version: SourceVersionEvidence,
        members: Vec<M3uGroupingMember>,
    ) -> Result<Self, M3uGroupingError> {
        if members.is_empty() {
            return Err(M3uGroupingError::Empty);
        }
        let mut content_ids = std::collections::BTreeSet::new();
        let mut source_ids = std::collections::BTreeSet::new();
        for (index, member) in members.iter().enumerate() {
            if member.ordinal() != index as u32 {
                return Err(M3uGroupingError::InvalidOrdinal);
            }
            if !content_ids.insert(member.game_content_id())
                || !source_ids.insert(member.source_version().source_entry_id())
            {
                return Err(M3uGroupingError::DuplicateMember);
            }
            if member.source_version().source_entry_id()
                == playlist_source_version.source_entry_id()
            {
                return Err(M3uGroupingError::PlaylistAppearsAsMember);
            }
        }
        Ok(Self {
            playlist_source_version,
            members,
        })
    }

    /// Returns the playlist's current source version.
    pub fn playlist_source_version(&self) -> &SourceVersionEvidence {
        &self.playlist_source_version
    }

    /// Returns ordered members in playlist order.
    pub fn members(&self) -> &[M3uGroupingMember] {
        &self.members
    }
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
        debug_assert_eq!(
            source_entry_id,
            source_version.source_entry_id(),
            "legacy derivation arguments must identify the same source entry"
        );
        Self::try_with_provenance(
            vec![ProvenanceMember::new(
                ContentProvenanceRole::Primary,
                Some(association_key),
                source_version,
            )],
            platform,
            content_type,
            identity,
            fallback_title,
        )
        .expect("single-source derivation always has a non-empty basis")
    }

    /// Creates a derivation from a non-empty exact provenance basis.
    pub fn try_with_provenance(
        provenance: Vec<ProvenanceMember>,
        platform: PlatformId,
        content_type: ContentType,
        identity: ContentIdentity,
        fallback_title: String,
    ) -> Result<Self, ProvenanceBasisError> {
        if provenance.is_empty() {
            return Err(ProvenanceBasisError::Empty);
        }
        Ok(Self {
            provenance,
            platform,
            content_type,
            identity,
            fallback_title,
        })
    }

    /// Returns the primary source, or the first exact member when no primary
    /// role was supplied by a format-specific derivation.
    pub fn source_entry_id(&self) -> SourceEntryId {
        let mut index = 0;
        while index < self.provenance.len() {
            if self.provenance[index].role() == ContentProvenanceRole::Primary {
                return self.provenance[index].source_entry_id();
            }
            index += 1;
        }
        self.provenance[0].source_entry_id()
    }

    /// Returns the primary source version, or the first exact member version.
    pub fn source_version(&self) -> &SourceVersionEvidence {
        self.provenance
            .iter()
            .find(|member| member.role() == ContentProvenanceRole::Primary)
            .unwrap_or(&self.provenance[0])
            .source_version()
    }

    /// Returns every exact provenance member in stable derivation order.
    pub fn provenance(&self) -> &[ProvenanceMember] {
        &self.provenance
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
        self.provenance
            .iter()
            .find(|member| member.role() == ContentProvenanceRole::Primary)
            .or_else(|| self.provenance.first())
            .and_then(|member| member.association_key())
            .unwrap_or("")
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

    /// Compares every source-version snapshot in one exact proof basis.
    fn source_versions_match(
        &mut self,
        evidence: &[SourceVersionEvidence],
    ) -> Result<bool, PersistenceError> {
        for member in evidence {
            if !self.source_version_matches(member)? {
                return Ok(false);
            }
        }
        Ok(true)
    }

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

    /// Applies one version-bound ordered M3U relationship in an atomic
    /// grouping transaction. Membership ordinals remain in grouping evidence,
    /// never in the durable GameMembership relationship.
    fn apply_m3u_grouping(
        &mut self,
        grouping: &ValidatedM3uGrouping,
    ) -> Result<GameId, PersistenceError>;

    /// Revokes current M3U evidence whose playlist was not successfully
    /// validated during the current refresh and restores independent
    /// provisional game membership for released discs.
    fn reconcile_m3u_grouping_evidence(
        &mut self,
        active_playlist_source_ids: &[SourceEntryId],
    ) -> Result<(), PersistenceError>;
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
        let evidence: Vec<SourceVersionEvidence> = derivation
            .provenance()
            .iter()
            .map(|member| member.source_version().clone())
            .collect();
        let matches = store
            .source_versions_match(&evidence)
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
