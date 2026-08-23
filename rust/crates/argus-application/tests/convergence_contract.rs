use argus_application::{
    ContentIdentity, ContentType, ConvergenceOutcome, ErrorCode, IdentificationService,
    IdentityConvergenceStore, IdentityDigest, OperationContext, OperationName, PlatformId,
    SafeContext, ScanRunId, SourceEntryId, SourceVersionEvidence, SubsystemName, TraceId,
    ValidatedContentDerivation,
};

struct FakeStore {
    source_matches: bool,
    converged: bool,
}

impl IdentityConvergenceStore for FakeStore {
    fn source_version_matches(
        &mut self,
        _evidence: &SourceVersionEvidence,
    ) -> Result<bool, argus_application::PersistenceError> {
        Ok(self.source_matches)
    }

    fn converge_identity(
        &mut self,
        _derivation: &ValidatedContentDerivation,
    ) -> Result<ConvergenceOutcome, argus_application::PersistenceError> {
        self.converged = true;
        Ok(ConvergenceOutcome::Created {
            game_content_id: argus_application::GameContentId::from_bytes([1; 16]).expect("id"),
            game_id: argus_application::GameId::from_bytes([2; 16]).expect("id"),
        })
    }
}

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(121_u128).expect("trace"),
        SubsystemName::try_from("content").expect("subsystem"),
        OperationName::try_from("identify").expect("operation"),
    )
}

fn derivation() -> ValidatedContentDerivation {
    ValidatedContentDerivation::new(
        SourceEntryId::from_bytes([3; 16]).expect("source"),
        SourceVersionEvidence::new(
            SourceEntryId::from_bytes([3; 16]).expect("source"),
            Some("v1:32:4".to_owned()),
            ScanRunId::from_bytes([4; 16]).expect("scan"),
        ),
        PlatformId::NintendoGb,
        ContentType::CartridgeImage,
        ContentIdentity::new(
            "argus.content.identity.nintendo-gb.cartridge.v1",
            1,
            IdentityDigest::from_bytes([5; 32]),
        ),
        "raw".to_owned(),
        "Game Boy".to_owned(),
    )
}

#[test]
fn stale_persisted_source_evidence_returns_published_source_changed_error() {
    let mut store = FakeStore {
        source_matches: false,
        converged: false,
    };
    let error = IdentificationService::converge(&mut store, derivation(), context())
        .expect_err("stale source");

    assert_eq!(
        error.code,
        ErrorCode::OperationSourceChangedDuringProcessing
    );
    assert!(!store.converged, "stale derivation must not converge");
    assert_eq!(error.safe_context, SafeContext::new());
}

#[test]
fn matching_persisted_source_evidence_converges_without_source_io() {
    let mut store = FakeStore {
        source_matches: true,
        converged: false,
    };
    let outcome = IdentificationService::converge(&mut store, derivation(), context())
        .expect("matching source");

    assert!(matches!(outcome, ConvergenceOutcome::Created { .. }));
    assert!(store.converged);
}
