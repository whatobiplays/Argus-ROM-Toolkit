use argus_application::{
    ContentProvenanceMemberSummary, ContentProvenanceRole, ContentProvenanceSummary,
    ProvenanceVersionError, ScanRunId, SourceEntryId,
};

fn source_entry_id() -> SourceEntryId {
    SourceEntryId::try_from("11111111111111111111111111111111").expect("source entry id")
}

fn scan_run_id() -> ScanRunId {
    ScanRunId::try_from("22222222222222222222222222222222").expect("scan run id")
}

#[test]
fn provenance_projections_reject_contradictory_provider_and_derived_evidence() {
    assert_eq!(
        ContentProvenanceSummary::new_with_version(
            source_entry_id(),
            "primary",
            Some("provider-v1".to_owned()),
            Some("derived-v1".to_owned()),
            scan_run_id(),
        ),
        Err(ProvenanceVersionError::BothFingerprintsPresent)
    );
    assert_eq!(
        ContentProvenanceMemberSummary::new_with_version(
            ContentProvenanceRole::Primary,
            Some("primary".to_owned()),
            source_entry_id(),
            Some("provider-v1".to_owned()),
            Some("derived-v1".to_owned()),
            scan_run_id(),
        ),
        Err(ProvenanceVersionError::BothFingerprintsPresent)
    );
}
