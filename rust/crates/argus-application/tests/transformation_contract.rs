use argus_application::{
    DerivedFingerprint, ErrorCode, SourceVersionKind, TransformationBudget, TransformationFailure,
    TransformationOutput, TransformationRegistry, map_transformation_failure,
};

#[test]
fn production_budget_matches_the_approved_safety_envelope() {
    assert_eq!(
        TransformationBudget::production(),
        TransformationBudget::new(
            16 * 1024 * 1024 * 1024,
            32 * 1024 * 1024 * 1024,
            65_536,
            4,
            16 * 1024 * 1024 * 1024,
            64 * 1024 * 1024 * 1024,
        )
    );
}

#[test]
fn source_version_distinguishes_provider_and_derived_evidence() {
    let derived =
        SourceVersionKind::Derived(DerivedFingerprint::from_transformation("df:v1".into()));
    assert_ne!(derived, SourceVersionKind::Provider(None));
}

#[test]
fn published_container_errors_match_be_012() {
    assert_eq!(
        ErrorCode::ValidationContentMalformed.as_str(),
        "ARGUS.V1.VALIDATION.CONTENT_MALFORMED"
    );
    assert_eq!(
        ErrorCode::ValidationContentUnsupportedRepresentation.as_str(),
        "ARGUS.V1.VALIDATION.CONTENT_UNSUPPORTED_REPRESENTATION"
    );
    assert_eq!(
        ErrorCode::ValidationContentEncryptedUnsupported.as_str(),
        "ARGUS.V1.VALIDATION.CONTENT_ENCRYPTED_UNSUPPORTED"
    );
    assert_eq!(
        ErrorCode::ValidationMultiGameContainerUnsupported.as_str(),
        "ARGUS.V1.VALIDATION.MULTI_GAME_CONTAINER_UNSUPPORTED"
    );
    assert_eq!(
        ErrorCode::FilesystemContentDependencyMissing.as_str(),
        "ARGUS.V1.FILESYSTEM.CONTENT_DEPENDENCY_MISSING"
    );
    assert_eq!(
        ErrorCode::ValidationContentRecognitionAmbiguous.as_str(),
        "ARGUS.V1.VALIDATION.CONTENT_RECOGNITION_AMBIGUOUS"
    );
    assert_eq!(
        ErrorCode::OperationTransformationResourceLimitExceeded.as_str(),
        "ARGUS.V1.OPERATION.TRANSFORMATION_RESOURCE_LIMIT_EXCEEDED"
    );
}

#[test]
fn transformation_failures_map_to_published_application_codes() {
    let mappings = [
        (
            TransformationFailure::NotApplicable,
            ErrorCode::ValidationContentUnsupportedRepresentation,
        ),
        (
            TransformationFailure::UnsupportedFeature,
            ErrorCode::ValidationContentUnsupportedRepresentation,
        ),
        (
            TransformationFailure::Malformed,
            ErrorCode::ValidationContentMalformed,
        ),
        (
            TransformationFailure::EncryptedUnsupported,
            ErrorCode::ValidationContentEncryptedUnsupported,
        ),
        (
            TransformationFailure::MultiGameUnsupported,
            ErrorCode::ValidationMultiGameContainerUnsupported,
        ),
        (
            TransformationFailure::MissingDependency,
            ErrorCode::FilesystemContentDependencyMissing,
        ),
        (
            TransformationFailure::AmbiguousRecognition,
            ErrorCode::ValidationContentRecognitionAmbiguous,
        ),
        (
            TransformationFailure::ResourceLimitExceeded,
            ErrorCode::OperationTransformationResourceLimitExceeded,
        ),
        (
            TransformationFailure::Cancelled,
            ErrorCode::OperationCancelled,
        ),
        (
            TransformationFailure::ReadFailure,
            ErrorCode::FilesystemSourceValidationIndeterminate,
        ),
        (
            TransformationFailure::SourceChanged,
            ErrorCode::OperationSourceChangedDuringProcessing,
        ),
    ];

    for (failure, expected) in mappings {
        assert_eq!(map_transformation_failure(failure), expected);
    }
}

#[test]
fn production_registry_advertises_only_the_approved_transformation_outputs() {
    let registry = TransformationRegistry::production();
    let expected = [
        "zip", "sevenzip", "tar", "gzip", "bzip2", "xz", "chd-cd", "chd-gd", "chd-dvd", "chd-umd",
        "rvz", "cso", "wbfs",
    ];

    for representation in expected {
        assert!(
            registry
                .descriptors()
                .iter()
                .any(|descriptor| descriptor.representation() == representation),
            "missing {representation}"
        );
    }
    assert!(
        registry
            .descriptors()
            .iter()
            .all(|descriptor| descriptor.representation() != "rar")
    );
    assert!(
        registry
            .descriptors()
            .iter()
            .any(|descriptor| descriptor.output() == TransformationOutput::DerivedScope)
    );
}
