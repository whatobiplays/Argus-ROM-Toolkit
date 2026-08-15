//! Application-contract tests for the Slice 004 source-entry hierarchy queries.

use std::cell::RefCell;
use std::rc::Rc;

use argus_application::{
    ErrorCode, GetSourceEntryHandler, GetSourceEntryQuery, ListSourceEntryChildrenHandler,
    ListSourceEntryChildrenQuery, OperationContext, OperationName, PersistenceError,
    SourceEntryChildrenPage, SourceEntryClassification, SourceEntryCursor, SourceEntryCursorError,
    SourceEntryDetailProjection, SourceEntryId, SourceEntryKind, SourceEntryProjection,
    SourceEntryQueries, SubsystemName, TraceId,
};

const ROOT_A: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const ENTRY_A: &str = "11111111111111111111111111111111";
const ENTRY_B: &str = "22222222222222222222222222222222";

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(1).expect("non-zero trace"),
        SubsystemName::try_from("test").expect("valid subsystem"),
        OperationName::try_from("sources").expect("valid operation"),
    )
}

fn root_id(value: &str) -> argus_application::LibraryRootId {
    argus_application::LibraryRootId::try_from(value).expect("fixture root id")
}

fn entry_id(value: &str) -> SourceEntryId {
    SourceEntryId::try_from(value).expect("fixture entry id")
}

fn row(id: &str, parent: Option<&str>) -> SourceEntryProjection {
    SourceEntryProjection::new(
        entry_id(id),
        parent.map(entry_id),
        "Name".to_owned(),
        "Location".to_owned(),
        SourceEntryKind::Directory,
        SourceEntryClassification::Container,
    )
}

fn detail(id: &str) -> SourceEntryDetailProjection {
    SourceEntryDetailProjection::new(
        entry_id(id),
        None,
        "Name".to_owned(),
        "Location".to_owned(),
        SourceEntryKind::File,
        SourceEntryClassification::Unknown,
    )
}

#[derive(Clone)]
struct FakeHierarchyQueries {
    page: Rc<RefCell<Result<SourceEntryChildrenPage, PersistenceError>>>,
    detail: Rc<RefCell<Result<Option<SourceEntryDetailProjection>, PersistenceError>>>,
}

impl Default for FakeHierarchyQueries {
    fn default() -> Self {
        Self {
            page: Rc::new(RefCell::new(Ok(SourceEntryChildrenPage::new(
                Vec::new(),
                None,
            )))),
            detail: Rc::new(RefCell::new(Ok(None))),
        }
    }
}

impl FakeHierarchyQueries {
    fn with_page(page: SourceEntryChildrenPage) -> Self {
        Self {
            page: Rc::new(RefCell::new(Ok(page))),
            detail: Rc::new(RefCell::new(Ok(None))),
        }
    }
}

impl SourceEntryQueries for FakeHierarchyQueries {
    fn list_children(
        &self,
        _context: &OperationContext,
        _query: &ListSourceEntryChildrenQuery,
    ) -> Result<SourceEntryChildrenPage, PersistenceError> {
        self.page.borrow().clone()
    }

    fn get(
        &self,
        _context: &OperationContext,
        _source_entry_id: SourceEntryId,
    ) -> Result<Option<SourceEntryDetailProjection>, PersistenceError> {
        self.detail.borrow().clone()
    }
}

#[test]
fn source_entry_cursor_round_trips_through_its_opaque_wire_form() {
    let cursor = SourceEntryCursor::from_paging_keys(1_700_000_000, entry_id(ENTRY_A));
    let wire = cursor.to_string();
    let decoded = SourceEntryCursor::try_from(wire.as_str()).expect("valid wire cursor");

    assert_eq!(decoded.created_at_seconds(), 1_700_000_000);
    assert_eq!(decoded.source_entry_id(), entry_id(ENTRY_A));
    assert_eq!(decoded, cursor);
}

#[test]
fn source_entry_cursor_rejects_malformed_external_text() {
    for value in [
        "",
        "v1",
        "v1:",
        "v1:abc:11111111111111111111111111111111",
        "v2:123:11111111111111111111111111111111",
        "v1:123:not-hex",
        "v1:-1:11111111111111111111111111111111",
        "v1:123:00000000000000000000000000000000",
        "v1:123:11111111111111111111111111111111:extra",
    ] {
        assert_eq!(
            SourceEntryCursor::try_from(value),
            Err(SourceEntryCursorError),
            "malformed cursor accepted: {value}"
        );
    }
}

#[test]
fn list_children_query_clamps_page_size_to_the_backend_bound() {
    let root = root_id(ROOT_A);
    assert_eq!(
        ListSourceEntryChildrenQuery::new(root, None, None, 0).page_size(),
        1
    );
    assert_eq!(
        ListSourceEntryChildrenQuery::new(root, None, None, 100).page_size(),
        100
    );
    assert_eq!(
        ListSourceEntryChildrenQuery::new(root, None, None, 999).page_size(),
        ListSourceEntryChildrenQuery::MAX_PAGE_SIZE
    );
    assert_eq!(ListSourceEntryChildrenQuery::DEFAULT_PAGE_SIZE, 100);
}

#[test]
fn list_source_entry_children_delegates_and_maps_persistence_failures() {
    let queries = FakeHierarchyQueries {
        page: Rc::new(RefCell::new(Err(PersistenceError::DatabaseLocked))),
        detail: Rc::new(RefCell::new(Ok(None))),
    };
    let handler = ListSourceEntryChildrenHandler::new(queries);

    let error = handler
        .handle(
            ListSourceEntryChildrenQuery::new(root_id(ROOT_A), None, None, 100),
            context(),
        )
        .expect_err("persistence failure maps to an application failure");

    assert_eq!(error.code, ErrorCode::PersistenceDatabaseLocked);
    assert_eq!(error.code.as_str(), "ARGUS.V1.PERSISTENCE.DATABASE_LOCKED");
}

#[test]
fn list_source_entry_children_returns_the_authoritative_page() {
    let page = SourceEntryChildrenPage::new(
        vec![row(ENTRY_A, None), row(ENTRY_B, None)],
        Some(SourceEntryCursor::from_paging_keys(
            1_700_000_000,
            entry_id(ENTRY_B),
        )),
    );
    let handler =
        ListSourceEntryChildrenHandler::new(FakeHierarchyQueries::with_page(page.clone()));

    let result = handler
        .handle(
            ListSourceEntryChildrenQuery::new(root_id(ROOT_A), None, None, 100),
            context(),
        )
        .expect("page");

    assert_eq!(result, page);
}

#[test]
fn get_source_entry_returns_the_authoritative_detail() {
    let queries = FakeHierarchyQueries {
        page: Rc::new(RefCell::new(Ok(SourceEntryChildrenPage::new(
            Vec::new(),
            None,
        )))),
        detail: Rc::new(RefCell::new(Ok(Some(detail(ENTRY_A))))),
    };
    let handler = GetSourceEntryHandler::new(queries);

    let result = handler
        .handle(GetSourceEntryQuery::new(entry_id(ENTRY_A)), context())
        .expect("detail");

    assert_eq!(result, detail(ENTRY_A));
}

#[test]
fn get_source_entry_maps_a_missing_entry_to_a_typed_configuration_failure() {
    let handler = GetSourceEntryHandler::new(FakeHierarchyQueries::default());

    let error = handler
        .handle(GetSourceEntryQuery::new(entry_id(ENTRY_A)), context())
        .expect_err("missing entry is an application failure");

    assert_eq!(error.code, ErrorCode::ConfigurationSourceEntryNotFound);
    assert_eq!(
        error.code.as_str(),
        "ARGUS.V1.CONFIGURATION.SOURCE_ENTRY_NOT_FOUND"
    );
    assert_eq!(
        error.message_key.as_str(),
        "errors.configuration.source_entry_not_found"
    );
}

#[test]
fn source_entry_projections_expose_only_safe_application_facts() {
    let row = row(ENTRY_A, Some(ENTRY_B));
    assert_eq!(row.source_entry_id(), entry_id(ENTRY_A));
    assert_eq!(row.parent_source_entry_id(), Some(entry_id(ENTRY_B)));
    assert_eq!(row.display_name(), "Name");
    assert_eq!(row.display_location(), "Location");
    assert_eq!(row.kind(), SourceEntryKind::Directory);
    assert_eq!(row.classification(), SourceEntryClassification::Container);

    let detail = detail(ENTRY_A);
    assert_eq!(detail.source_entry_id(), entry_id(ENTRY_A));
    assert_eq!(detail.parent_source_entry_id(), None);
    assert_eq!(detail.display_name(), "Name");
    assert_eq!(detail.display_location(), "Location");
    assert_eq!(detail.kind(), SourceEntryKind::File);
    assert_eq!(detail.classification(), SourceEntryClassification::Unknown);
}
