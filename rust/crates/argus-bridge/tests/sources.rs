//! Bridge contract tests for the Slice 001 Sources surface.

use argus_application::{
    AddLocalLibraryRootResult, ApplicationError, ErrorCode, LibraryRootActiveScanSummary,
    LibraryRootAvailability, LibraryRootId, LibraryRootLastScanStatus, LibraryRootLastScanSummary,
    LibraryRootProjection, RemoveLibraryRootResult,
};
use argus_bridge::{
    AddLocalLibraryRootResultDto, LibraryRootAvailabilityDto, LibraryRootLastScanStatusDto,
    RemoveLibraryRootResultDto, RootRelationshipDto, RuntimeEventPayloadDto,
    add_local_library_root_dto, library_root_dto, library_root_page_dto, parse_library_root_id,
    remove_library_root_dto, runtime_event_dto,
};
use argus_runtime::{RuntimeEvent, RuntimeEventPayload, RuntimeInstanceId};

fn trace_id() -> argus_application::TraceId {
    argus_application::TraceId::try_from([1; 16]).expect("non-zero trace")
}

fn root_id(value: &str) -> LibraryRootId {
    LibraryRootId::try_from(value).expect("fixture root id")
}

fn projection() -> LibraryRootProjection {
    LibraryRootProjection::new(
        root_id("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
        "Games".to_owned(),
        "/library/Games".to_owned(),
        LibraryRootAvailability::Available,
        None,
        None,
    )
}

#[test]
fn library_root_dto_preserves_independent_projection_dimensions() {
    let last_scan = LibraryRootLastScanSummary::new(
        "scan".to_owned(),
        "job".to_owned(),
        LibraryRootLastScanStatus::Partial,
        10,
        Some(20),
    );
    let active_scan = LibraryRootActiveScanSummary::new("scan".to_owned(), "job".to_owned());
    let root = projection()
        .with_last_scan(last_scan)
        .with_active_scan(active_scan);

    let dto = library_root_dto(&root);

    assert_eq!(dto.library_root_id, root.root_id().to_string());
    assert_eq!(dto.display_name, "Games");
    assert_eq!(dto.safe_location_presentation, "/library/Games");
    assert_eq!(dto.availability, LibraryRootAvailabilityDto::Available);
    let last = dto.last_scan.expect("last scan");
    assert_eq!(last.scan_run_id, "scan");
    assert_eq!(last.job_run_id, "job");
    assert_eq!(last.status, LibraryRootLastScanStatusDto::Partial);
    assert_eq!(last.started_at_ms, 10);
    assert_eq!(last.completed_at_ms, Some(20));
    let active = dto.active_scan.expect("active scan");
    assert_eq!(active.scan_run_id, "scan");
    assert_eq!(active.job_run_id, "job");
}

#[test]
fn library_root_dto_never_exposes_locator_internals() {
    let dto = library_root_dto(&projection());

    assert!(!dto.display_name.contains('/'));
    assert!(!dto.safe_location_presentation.contains("locator"));
    assert!(dto.last_scan.is_none());
    assert!(dto.active_scan.is_none());
}

#[test]
fn library_root_page_dto_preserves_bounded_paging_facts() {
    let page = argus_application::LibraryRootPage::new(vec![projection()], 0, 10, 1);

    let dto = library_root_page_dto(&page);

    assert_eq!(dto.items.len(), 1);
    assert_eq!(dto.offset, 0);
    assert_eq!(dto.page_size, 10);
    assert_eq!(dto.total_count, 1);
}

#[test]
fn add_result_maps_every_typed_outcome_without_application_failure_shapes() {
    let added = AddLocalLibraryRootResult::Added(projection());
    match add_local_library_root_dto(&added) {
        AddLocalLibraryRootResultDto::Added(dto) => {
            assert_eq!(
                dto.library_root_id,
                root_id("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa").to_string()
            );
        }
        _ => panic!("expected Added"),
    }

    let already =
        AddLocalLibraryRootResult::AlreadyConfigured(root_id("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"));
    match add_local_library_root_dto(&already) {
        AddLocalLibraryRootResultDto::AlreadyConfigured(id) => {
            assert_eq!(id, root_id("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb").to_string());
        }
        _ => panic!("expected AlreadyConfigured"),
    }

    let overlap = AddLocalLibraryRootResult::OverlapsExisting(
        root_id("cccccccccccccccccccccccccccccccc"),
        argus_application::RootRelationship::Ancestor,
    );
    match add_local_library_root_dto(&overlap) {
        AddLocalLibraryRootResultDto::OverlapsExisting(id, relationship) => {
            assert_eq!(id, root_id("cccccccccccccccccccccccccccccccc").to_string());
            assert_eq!(relationship, RootRelationshipDto::Ancestor);
        }
        _ => panic!("expected OverlapsExisting"),
    }
}

#[test]
fn remove_result_maps_the_slice_outcome() {
    assert_eq!(
        remove_library_root_dto(&RemoveLibraryRootResult::Removed),
        RemoveLibraryRootResultDto::Removed
    );
}

#[test]
fn library_root_id_parsing_is_typed_and_malformed_values_fail() {
    let valid =
        parse_library_root_id("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", trace_id()).expect("valid id");
    assert_eq!(valid, root_id("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"));

    let error = parse_library_root_id("not-an-id", trace_id()).expect_err("malformed id");
    assert_eq!(error.code, "ARGUS.V1.VALIDATION.INVALID_ARGUMENT");
}

#[test]
fn runtime_event_dto_maps_sources_payloads_without_snapshots() {
    let id = RuntimeInstanceId::from_hex("1234567890abcdef1234567890abcdef").expect("instance");
    let roots_changed = RuntimeEvent {
        runtime_instance_id: id,
        sequence: 1,
        occurred_at_ms: 100,
        payload: RuntimeEventPayload::LibraryRootsChanged,
    };
    let root_changed = RuntimeEvent {
        runtime_instance_id: id,
        sequence: 2,
        occurred_at_ms: 101,
        payload: RuntimeEventPayload::LibraryRootChanged {
            library_root_id: root_id("dddddddddddddddddddddddddddddddd"),
        },
    };

    let roots_dto = runtime_event_dto(&roots_changed);
    assert!(matches!(
        roots_dto.payload,
        RuntimeEventPayloadDto::LibraryRootsChanged
    ));
    let root_dto = runtime_event_dto(&root_changed);
    match root_dto.payload {
        RuntimeEventPayloadDto::LibraryRootChanged { library_root_id } => {
            assert_eq!(library_root_id, "dddddddddddddddddddddddddddddddd");
        }
        _ => panic!("expected LibraryRootChanged"),
    }
}

#[test]
fn missing_root_application_error_maps_to_the_stable_configuration_code() {
    let error = ApplicationError::from_code(
        ErrorCode::ConfigurationLibraryRootNotFound,
        trace_id(),
        argus_application::SafeContext::new(),
    )
    .expect("catalog error");

    let dto = argus_bridge::application_error_dto(&error);

    assert_eq!(dto.code, "ARGUS.V1.CONFIGURATION.LIBRARY_ROOT_NOT_FOUND");
    assert_eq!(
        dto.message_key,
        "errors.configuration.library_root_not_found"
    );
}
