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
    if references.is_empty() {
        return Err(OpticalDependencyError::Missing);
    }
    if references.len() > MAX_OPTICAL_DEPENDENCIES {
        return Err(OpticalDependencyError::ResourceLimitExceeded);
    }

    let descriptor = normalize_relative(descriptor_locator.as_provider_value())
        .ok_or(OpticalDependencyError::InvalidReference)?;
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

        let matches: Vec<&SourceEntryRecord> = candidates
            .iter()
            .filter(|candidate| candidate.kind() == SourceEntryKind::File)
            .filter(|candidate| {
                normalize_relative(candidate.relative_locator().as_provider_value()).as_deref()
                    == Some(normalized.as_str())
            })
            .collect();
        let [entry] = matches.as_slice() else {
            return if matches.is_empty() {
                Err(OpticalDependencyError::Missing)
            } else {
                Err(OpticalDependencyError::Ambiguous)
            };
        };
        if resolved.iter().any(|existing: &SourceEntryRecord| {
            existing.source_entry_id() == entry.source_entry_id()
        }) {
            return Err(OpticalDependencyError::Duplicate);
        }
        resolved.push((*entry).clone());
    }
    Ok(resolved)
}

fn normalize_reference(reference: &str) -> Result<String, OpticalDependencyError> {
    if reference.trim().is_empty() {
        return Err(OpticalDependencyError::InvalidReference);
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
