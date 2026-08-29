//! Application-owned reconciliation and admission rules for derived sources.
//!
//! Infrastructure decoders report opaque, validated member observations. This
//! module turns those observations into durable source-graph rows and keeps
//! archive eligibility separate from logical content convergence.

use std::collections::HashSet;

use sha2::{Digest, Sha256};

use crate::{
    DerivedEntryKey, DerivedEntryObservation, DerivedScopeOutcome, LibraryRootId, NewSourceEntry,
    PersistenceError, ScanRunId, SourceEntryClassification, SourceEntryId, SourceEntryKind,
    SourceEntryRepository,
};

/// Exact identity of one transformation-owned child scope.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct DerivedScopeIdentity<'a> {
    /// Stable source identity of the containing provider or derived entry.
    pub parent_source_entry_id: SourceEntryId,
    /// Registered transformation identifier owned by infrastructure.
    pub transformation_id: &'a str,
    /// Revision of the transformation contract.
    pub transformation_revision: u32,
}

/// Outcome of applying the single-game archive rule to validated content
/// families. Sidecars are not passed as families by the caller.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ArchiveEligibility<T> {
    /// No independently usable content family was recognized.
    NoSupportedGame,
    /// Exactly one independently usable content family remains admissible.
    SingleGame(T),
}

/// Application-level rejection for an archive containing multiple games.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ArchiveAdmissionError {
    /// More than one independently usable content family was found.
    MultiGameUnsupported,
}

/// Applies the archive-level single-game rule before any logical convergence.
///
/// Callers should pass only independently usable content families. A validated
/// descriptor plus its required members is one family, and sidecars are
/// intentionally omitted. Repeated evidence for the same family is collapsed
/// before the admission decision.
pub fn evaluate_archive_eligibility<T>(
    families: &[T],
) -> Result<ArchiveEligibility<T>, ArchiveAdmissionError>
where
    T: Clone + Eq + std::hash::Hash,
{
    let mut seen = HashSet::with_capacity(families.len());
    let mut unique = Vec::new();
    for family in families {
        if seen.insert(family) {
            unique.push(family.clone());
        }
    }
    match unique.len() {
        0 => Ok(ArchiveEligibility::NoSupportedGame),
        1 => Ok(ArchiveEligibility::SingleGame(unique.remove(0))),
        _ => Err(ArchiveAdmissionError::MultiGameUnsupported),
    }
}

/// Reconciles one validated derived scope into the source graph.
///
/// Positive observations require stable input because a decoder must never
/// persist an interpretation that was read from a changing source. Complete
/// stable enumeration is the only outcome allowed to finalize absence; all
/// other outcomes leave older derived rows untouched. `observed_at_seconds`
/// uses the same Unix-seconds unit as persisted source-entry timestamps.
pub fn reconcile_derived_scope(
    entries: &mut impl SourceEntryRepository,
    scope: &DerivedScopeIdentity<'_>,
    observations: &[DerivedEntryObservation],
    observation_run_id: ScanRunId,
    observed_at_seconds: i64,
    stable_input: bool,
    outcome: DerivedScopeOutcome,
) -> Result<Vec<SourceEntryId>, PersistenceError> {
    if !stable_input {
        return Ok(Vec::new());
    }

    if scope.transformation_revision == 0 || scope.transformation_id.is_empty() {
        return Err(PersistenceError::ConstraintViolation);
    }

    let library_root_id = entries.library_root_id_for_entry(scope.parent_source_entry_id)?;
    let mut reconciled = Vec::with_capacity(observations.len());
    for observation in observations {
        let existing = entries.find_derived_child(
            scope.parent_source_entry_id,
            scope.transformation_id,
            scope.transformation_revision,
            observation.derived_entry_key(),
        )?;
        let source_entry_id = existing
            .map(|entry| entry.source_entry_id())
            .unwrap_or_else(|| {
                stable_derived_source_entry_id(
                    scope.parent_source_entry_id,
                    scope.transformation_id,
                    scope.transformation_revision,
                    observation.derived_entry_key(),
                )
            });
        let classification = match observation.kind() {
            SourceEntryKind::Directory => SourceEntryClassification::Container,
            SourceEntryKind::File => SourceEntryClassification::SupportingEntry,
            SourceEntryKind::LinkLike | SourceEntryKind::Unknown => {
                SourceEntryClassification::Ignored
            }
        };
        let entry = NewSourceEntry::new_derived(
            source_entry_id,
            library_root_id,
            scope.parent_source_entry_id,
            observation.display_name().to_owned(),
            observation.display_location().to_owned(),
            observation.kind(),
            classification,
            observation.derived_locator().clone(),
            observation.derived_entry_key().clone(),
            observation.derived_fingerprint().clone(),
            scope.transformation_id.to_owned(),
            scope.transformation_revision,
            observation_run_id,
            observed_at_seconds,
            observed_at_seconds,
        );
        reconciled.push(entries.upsert_derived(entry)?);
    }

    if outcome == DerivedScopeOutcome::Complete {
        entries.finalize_absent_derived_scope(
            scope.parent_source_entry_id,
            scope.transformation_id,
            scope.transformation_revision,
            observation_run_id,
        )?;
    }
    Ok(reconciled)
}

fn stable_derived_source_entry_id(
    parent_source_entry_id: SourceEntryId,
    transformation_id: &str,
    transformation_revision: u32,
    key: &DerivedEntryKey,
) -> SourceEntryId {
    let mut hasher = Sha256::new();
    hasher.update(b"argus-derived-source-entry-id-v1");
    hasher.update(parent_source_entry_id.as_bytes());
    hasher.update((transformation_id.len() as u64).to_be_bytes());
    hasher.update(transformation_id.as_bytes());
    hasher.update(transformation_revision.to_be_bytes());
    hasher.update((key.as_transformation_value().len() as u64).to_be_bytes());
    hasher.update(key.as_transformation_value().as_bytes());
    let digest = hasher.finalize();
    let mut bytes = [0_u8; 16];
    bytes.copy_from_slice(&digest[..16]);
    if bytes == [0; 16] {
        bytes[15] = 1;
    }
    SourceEntryId::from_bytes(bytes).expect("derived source-entry identity is non-zero")
}

/// Keeps a root ID type in this module's public documentation and prevents
/// callers from mistaking the derived scope key for a provider locator.
#[allow(dead_code)]
fn _root_is_resolved_from_parent(_root: LibraryRootId) {}
