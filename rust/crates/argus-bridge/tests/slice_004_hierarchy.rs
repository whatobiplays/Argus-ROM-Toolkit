//! Bridge contract tests for the Slice 004 source-entry hierarchy DTOs and
//! cursor validation boundary.

use argus_application::{
    LibraryRootId, SourceEntryChildrenPage, SourceEntryClassification, SourceEntryCursor,
    SourceEntryDetailProjection, SourceEntryId, SourceEntryKind, SourceEntryProjection,
};
use argus_bridge::{
    ApplicationErrorDto, ListSourceEntryChildrenRequestDto, SourceEntryClassificationDto,
    SourceEntryKindDto, parse_source_entry_cursor, parse_source_entry_id,
    source_entry_children_page_dto, source_entry_detail_projection_dto,
    source_entry_projection_dto,
};

fn trace_id() -> argus_application::TraceId {
    argus_application::TraceId::try_from([1; 16]).expect("non-zero trace")
}

fn entry_id(value: &str) -> SourceEntryId {
    SourceEntryId::try_from(value).expect("fixture entry id")
}

fn projection() -> SourceEntryProjection {
    SourceEntryProjection::new(
        entry_id("11111111111111111111111111111111"),
        None,
        "a.bin".to_owned(),
        "a.bin".to_owned(),
        SourceEntryKind::File,
        SourceEntryClassification::Unknown,
    )
}

fn detail() -> SourceEntryDetailProjection {
    SourceEntryDetailProjection::new(
        entry_id("22222222222222222222222222222222"),
        Some(entry_id("33333333333333333333333333333333")),
        "Sub".to_owned(),
        "Sub".to_owned(),
        SourceEntryKind::Directory,
        SourceEntryClassification::Container,
    )
}

#[test]
fn source_entry_dto_preserves_safe_fields_and_reserved_status_is_none() {
    let dto = source_entry_projection_dto(&projection());

    assert_eq!(dto.source_entry_id, "11111111111111111111111111111111");
    assert_eq!(dto.parent_source_entry_id, None);
    assert_eq!(dto.display_name, "a.bin");
    assert_eq!(dto.display_location, "a.bin");
    assert_eq!(dto.kind, SourceEntryKindDto::File);
    assert_eq!(dto.classification, SourceEntryClassificationDto::Unknown);
    assert_eq!(dto.bounded_status_summary, None);
}

#[test]
fn source_entry_detail_dto_preserves_safe_fields_and_reserved_status_is_none() {
    let dto = source_entry_detail_projection_dto(&detail());

    assert_eq!(dto.source_entry_id, "22222222222222222222222222222222");
    assert_eq!(
        dto.parent_source_entry_id,
        Some("33333333333333333333333333333333".to_owned())
    );
    assert_eq!(dto.display_name, "Sub");
    assert_eq!(dto.display_location, "Sub");
    assert_eq!(dto.kind, SourceEntryKindDto::Directory);
    assert_eq!(dto.classification, SourceEntryClassificationDto::Container);
    assert_eq!(dto.bounded_status_summary, None);
    assert_eq!(dto.bounded_observation_status_detail, None);
}

#[test]
fn source_entry_page_dto_carries_an_opaque_next_cursor() {
    let page = SourceEntryChildrenPage::new(
        vec![projection()],
        Some(SourceEntryCursor::from_paging_keys(
            1_700_000_000,
            entry_id("11111111111111111111111111111111"),
        )),
    );

    let dto = source_entry_children_page_dto(&page);

    assert_eq!(dto.items.len(), 1);
    assert_eq!(
        dto.items[0].source_entry_id,
        "11111111111111111111111111111111"
    );
    let cursor = dto.next_cursor.expect("opaque cursor");
    assert!(!cursor.is_empty());
}

#[test]
fn parse_source_entry_id_rejects_malformed_external_ids() {
    let error = parse_source_entry_id("not-an-id", trace_id()).expect_err("malformed id");
    assert_eq!(error.code, "ARGUS.V1.VALIDATION.INVALID_ARGUMENT");
    assert_eq!(error.category, "validation");

    let parsed =
        parse_source_entry_id("44444444444444444444444444444444", trace_id()).expect("valid id");
    assert_eq!(parsed, entry_id("44444444444444444444444444444444"));
}

#[test]
fn parse_source_entry_cursor_rejects_malformed_external_cursor_text() {
    let error = parse_source_entry_cursor(Some("garbage-cursor".to_owned()), trace_id())
        .expect_err("malformed cursor");
    assert_eq!(error.code, "ARGUS.V1.VALIDATION.INVALID_ARGUMENT");

    assert_eq!(
        parse_source_entry_cursor(None, trace_id()).expect("null cursor"),
        None
    );
    let valid = parse_source_entry_cursor(
        Some("v1:1700000000:44444444444444444444444444444444".to_owned()),
        trace_id(),
    )
    .expect("valid cursor");
    assert_eq!(
        valid,
        Some(SourceEntryCursor::from_paging_keys(
            1_700_000_000,
            entry_id("44444444444444444444444444444444")
        ))
    );
}

#[test]
fn list_source_entry_children_request_dto_shapes_the_external_boundary() {
    let request = ListSourceEntryChildrenRequestDto {
        library_root_id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_owned(),
        parent_source_entry_id: None,
        cursor: None,
        page_size: 100,
    };
    assert_eq!(
        request.library_root_id,
        LibraryRootId::try_from("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
            .expect("root id")
            .to_string()
    );
    assert_eq!(request.page_size, 100);
}

#[test]
fn bridge_dto_validation_failures_are_application_failures() {
    let error: ApplicationErrorDto = parse_source_entry_cursor(
        Some("v1:not-a-number:44444444444444444444444444444444".to_owned()),
        trace_id(),
    )
    .expect_err("malformed cursor");
    assert_eq!(error.code, "ARGUS.V1.VALIDATION.INVALID_ARGUMENT");
    assert_eq!(error.message_key, "errors.validation.invalid_argument");
}
