use argus_application::{
    ApplicationPortError, GameListCursor, GetGameResult, IdentityRevisionFencedGameLibraryPage,
    LibraryFacetQuery, LibraryFilter, LibraryIdentityViewTokenV2, LibraryRootAvailability,
    LibraryRootId, LibraryRootRepository, LibraryScope, LibrarySort, LibraryViewToken,
    ListGamesQuery, LogicalContentUnitOfWork, LogicalLibraryQueries, OperationContext,
    OperationName, PersistenceError, RevisionFencedGameLibraryPage, SubsystemName, TraceId,
    UnitOfWork, UnitOfWorkFactory,
};
use argus_domain::HydrationState;
use argus_infrastructure::sqlite::{
    DEFAULT_QUEUE_CAPACITY, MigrationRegistry, ObserverCancellationHandle, SqliteDatabaseExecutor,
    SqliteExecutorError, observer_v1,
};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Barrier, Mutex, mpsc};
use std::thread;
use std::time::Duration;
use tempfile::tempdir;

/// Mirrors the reviewed closed membership result for host size measurements.
#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct MeasuredMembershipResult {
    query: &'static str,
    page_size: u32,
    page_count: u64,
    identity_membership_revision: i64,
    identity_view_contract_version: u32,
    query_contract_version: i64,
    game_ids: Vec<String>,
    member_identity_bindings: Vec<MeasuredMemberBinding>,
    prior_lookups: Vec<MeasuredPriorLookup>,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct MeasuredMemberBinding {
    requested_game_id: String,
    result: MeasuredFoundMember,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct MeasuredFoundMember {
    kind: &'static str,
    game_id: String,
    lifecycle: &'static str,
    content_identities: Vec<MeasuredContentIdentity>,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct MeasuredContentIdentity {
    platform_id: String,
    content_type: String,
    scheme_id: String,
    revision: u32,
    digest: String,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct MeasuredPriorLookup {
    requested_game_id: String,
    result: MeasuredGameNotFound,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct MeasuredGameNotFound {
    kind: &'static str,
    application_error: MeasuredApplicationError,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct MeasuredApplicationError {
    code: &'static str,
    category: &'static str,
    severity: &'static str,
    recoverability: &'static str,
    retry_policy: &'static str,
    message_key: &'static str,
    trace_id: &'static str,
    safe_context: Vec<String>,
}

struct TestDatabase {
    _directory: tempfile::TempDir,
    executor: SqliteDatabaseExecutor,
}

fn context(operation: &str) -> OperationContext {
    OperationContext::new(
        TraceId::try_from(28_u128).expect("trace"),
        SubsystemName::try_from("library_view_revision").expect("subsystem"),
        OperationName::try_from(operation).expect("operation"),
    )
}

fn open() -> TestDatabase {
    open_with_key([0x4d; 32])
}

fn open_with_key(key: [u8; 32]) -> TestDatabase {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("library.sqlite3");
    let executor =
        SqliteDatabaseExecutor::open_with_capacity_and_view_key(path, DEFAULT_QUEUE_CAPACITY, key)
            .expect("database opens");
    TestDatabase {
        _directory: directory,
        executor,
    }
}

fn list_query(
    cursor: Option<GameListCursor>,
    page_size: u32,
    search: Option<&str>,
) -> ListGamesQuery {
    ListGamesQuery::builder()
        .scope(LibraryScope::All)
        .search(search.map(str::to_owned))
        .filters_empty(true)
        .sort(LibrarySort::DisplayTitleAscending)
        .cursor(cursor)
        .page_size(page_size)
        .build()
        .expect("valid Library query")
}

fn fenced_list(
    executor: &SqliteDatabaseExecutor,
    query: ListGamesQuery,
    token: Option<LibraryViewToken>,
) -> Result<RevisionFencedGameLibraryPage, ApplicationPortError> {
    executor.execute(&context("fenced_list"), move |mut work| {
        let page = {
            let mut logical = work.logical_content();
            logical.list_games_revision_fenced(&query, token.as_ref())?
        };
        work.commit()?;
        Ok(page)
    })
}

fn fenced_identity_list(
    executor: &SqliteDatabaseExecutor,
    query: ListGamesQuery,
    token: Option<LibraryIdentityViewTokenV2>,
) -> Result<IdentityRevisionFencedGameLibraryPage, ApplicationPortError> {
    executor.execute(&context("fenced_identity_list"), move |mut work| {
        let page = {
            let mut logical = work.logical_content();
            logical.list_games_identity_revision_fenced(&query, token.as_ref())?
        };
        work.commit()?;
        Ok(page)
    })
}

fn fenced_identity_game(
    executor: &SqliteDatabaseExecutor,
    game_id: argus_domain::GameId,
    token: LibraryIdentityViewTokenV2,
) -> Result<GetGameResult, ApplicationPortError> {
    executor.execute(&context("fenced_identity_game"), move |mut work| {
        let game = {
            let mut logical = work.logical_content();
            logical.get_game_identity_revision_fenced(game_id, &token)?
        };
        work.commit()?;
        Ok(game)
    })
}

fn observer_identity_list(
    executor: &SqliteDatabaseExecutor,
    query: ListGamesQuery,
    token: Option<LibraryIdentityViewTokenV2>,
    cancellation: ObserverCancellationHandle,
) -> Result<IdentityRevisionFencedGameLibraryPage, SqliteExecutorError> {
    executor.with_observer_unit_of_work_for_tests(
        context("observer_identity_list"),
        cancellation,
        move |mut work| {
            let page = {
                let mut logical = work.logical_content();
                logical.list_games_identity_revision_fenced(&query, token.as_ref())?
            };
            Ok(page)
        },
    )
}

fn observer_identity_game(
    executor: &SqliteDatabaseExecutor,
    game_id: argus_domain::GameId,
    token: LibraryIdentityViewTokenV2,
    cancellation: ObserverCancellationHandle,
) -> Result<GetGameResult, SqliteExecutorError> {
    executor.with_observer_unit_of_work_for_tests(
        context("observer_identity_game"),
        cancellation,
        move |mut work| {
            let game = {
                let mut logical = work.logical_content();
                logical.get_game_identity_revision_fenced(game_id, &token)?
            };
            Ok(game)
        },
    )
}

fn fenced_game(
    executor: &SqliteDatabaseExecutor,
    game_id: argus_domain::GameId,
    token: LibraryViewToken,
) -> Result<GetGameResult, ApplicationPortError> {
    executor.execute(&context("fenced_game"), move |mut work| {
        let result = {
            let mut logical = work.logical_content();
            logical.get_game_revision_fenced(game_id, &token)?
        };
        work.commit()?;
        Ok(result)
    })
}

fn insert_two_games(executor: &SqliteDatabaseExecutor) {
    write(
        executor,
        "INSERT INTO game (
            game_id, platform_id, lifecycle_state, grouping_revision, fallback_title,
            fallback_title_provenance, hydration_state, created_at, updated_at
         ) VALUES
            ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'nintendo.gb', 'active', 1,
             'Alpha One', 'local_fallback', 'partially_hydrated', '1', '1'),
            ('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'nintendo.gb', 'active', 1,
             'Alpha Two', 'local_fallback', 'partially_hydrated', '1', '1');
         INSERT INTO game_library_row (
            game_id, display_title, display_title_provenance, platform_id,
            presentation_region, selected_cover_asset_id, release_date, search_text,
            hydration_state, availability_state, content_count, source_count, updated_at
         ) VALUES
            ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Alpha One', 'local_fallback', 'nintendo.gb',
             NULL, NULL, NULL, 'alpha one', 'partially_hydrated', 'available', 0, 0, '1'),
            ('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'Alpha Two', 'local_fallback', 'nintendo.gb',
             NULL, NULL, NULL, 'alpha two', 'partially_hydrated', 'available', 0, 0, '1');",
    );
}

fn insert_two_games_with_roots(executor: &SqliteDatabaseExecutor) {
    write(
        executor,
        "INSERT INTO library_source (
            library_source_id, source_provider_type, display_name, provider_config,
            config_revision, created_at, updated_at
         ) VALUES (
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'local_filesystem', 'Test source',
            '{}', 1, '1', '1'
         );
         INSERT INTO library_root (
            library_root_id, library_source_id, root_locator, display_name,
            safe_location_presentation, availability_status, config_revision,
            created_at, updated_at
         ) VALUES
            ('cccccccccccccccccccccccccccccccc', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
             'root-a', 'Root A', 'Root A', 'available', 1, '1', '1'),
            ('dddddddddddddddddddddddddddddddd', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
             'root-b', 'Root B', 'Root B', 'available', 1, '1', '1');
         INSERT INTO source_entry (
            source_entry_id, library_root_id, parent_source_entry_id, coordinate_kind,
            relative_locator, locator_key, display_name, display_location, kind,
            classification, provider_native_identity, source_fingerprint,
            derived_locator, derived_entry_key, derived_fingerprint,
            derivation_transformation_id, derivation_revision,
            last_observed_scan_id, created_at, updated_at
         ) VALUES
            ('eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee', 'cccccccccccccccccccccccccccccccc',
             NULL, 'provider', 'a.gb', 'a.gb', 'a.gb', 'a.gb', 'file',
             'content_candidate', NULL, NULL, NULL, NULL, NULL, NULL, NULL, '', 1, 1),
            ('12121212121212121212121212121212', 'dddddddddddddddddddddddddddddddd',
             NULL, 'provider', 'b.gb', 'b.gb', 'b.gb', 'b.gb', 'file',
             'content_candidate', NULL, NULL, NULL, NULL, NULL, NULL, NULL, '', 1, 1);
         INSERT INTO game_content (
            game_content_id, platform_id, content_type, presence_state,
            identification_state, grouping_revision, created_at, updated_at
         ) VALUES
            ('ffffffffffffffffffffffffffffffff', 'nintendo.gb', 'CartridgeImage',
             'available', 'unidentified', 1, '1', '1'),
            ('99999999999999999999999999999999', 'nintendo.gb', 'CartridgeImage',
             'available', 'unidentified', 1, '1', '1');
         INSERT INTO game_content_source (
            game_content_source_id, game_content_id, source_entry_id,
            association_key, source_fingerprint, last_observed_scan_id,
            is_current, created_at, updated_at
         ) VALUES
            ('11111111111111111111111111111111',
             'ffffffffffffffffffffffffffffffff', 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
             'primary', NULL, NULL, 1, '1', '1'),
            ('13131313131313131313131313131313',
             '99999999999999999999999999999999', '12121212121212121212121212121212',
             'primary', NULL, NULL, 1, '1', '1');
         INSERT INTO game (
            game_id, platform_id, lifecycle_state, grouping_revision, fallback_title,
            fallback_title_provenance, hydration_state, created_at, updated_at
         ) VALUES
            ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'nintendo.gb', 'active', 1,
             'Alpha One', 'local_fallback', 'partially_hydrated', '1', '1'),
            ('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'nintendo.gb', 'active', 1,
             'Alpha Two', 'local_fallback', 'partially_hydrated', '1', '1');
         INSERT INTO game_membership (
            game_membership_id, game_id, game_content_id, relationship,
            grouping_basis, grouping_revision, is_current, created_at, updated_at
         ) VALUES
            ('22222222222222222222222222222222',
             'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'ffffffffffffffffffffffffffffffff',
             'primary_content', 'provisional', 1, 1, '1', '1'),
            ('14141414141414141414141414141414',
             'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', '99999999999999999999999999999999',
             'primary_content', 'provisional', 1, 1, '1', '1');
         INSERT INTO game_library_row (
            game_id, display_title, display_title_provenance, platform_id,
            presentation_region, selected_cover_asset_id, release_date, search_text,
            hydration_state, availability_state, content_count, source_count, updated_at
         ) VALUES
            ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Alpha One', 'local_fallback', 'nintendo.gb',
             NULL, NULL, NULL, 'alpha one', 'partially_hydrated', 'available', 1, 1, '1'),
            ('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'Alpha Two', 'local_fallback', 'nintendo.gb',
             NULL, NULL, NULL, 'alpha two', 'partially_hydrated', 'available', 1, 1, '1');",
    );
}

fn seed_identity_membership_fixture(executor: &SqliteDatabaseExecutor) {
    insert_two_games_with_roots(executor);
    write(
        executor,
        "UPDATE game_content SET identification_state = 'identified'
         WHERE game_content_id IN (
             'ffffffffffffffffffffffffffffffff',
             '99999999999999999999999999999999'
         );
         INSERT INTO content_identity (
             content_identity_id, game_content_id, scheme_id, identity_revision,
             identity_value, is_current, created_at, updated_at
         ) VALUES
         ('15151515151515151515151515151515',
          'ffffffffffffffffffffffffffffffff',
          'argus.content.identity.nintendo-gb.cartridge.v1', 1,
          '0909090909090909090909090909090909090909090909090909090909090909',
          1, '1', '1'),
         ('16161616161616161616161616161616',
          '99999999999999999999999999999999',
          'argus.content.identity.nintendo-gb.cartridge.v1', 1,
          '0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a',
          1, '1', '1');",
    );
}

fn measured_member_binding(
    requested_game_id: String,
    result: GetGameResult,
) -> MeasuredMemberBinding {
    let GetGameResult::Found(detail) = result else {
        panic!("listed GameId must have a complete same-view detail");
    };
    let content_identities = detail
        .content()
        .iter()
        .map(|content| {
            let identity = content.identity().expect("current identity is complete");
            let digest = identity
                .digest()
                .as_bytes()
                .iter()
                .map(|byte| format!("{byte:02x}"))
                .collect::<String>();
            MeasuredContentIdentity {
                platform_id: content.platform_id().as_str().to_owned(),
                content_type: content.content_type().as_str().to_owned(),
                scheme_id: identity.scheme_id().to_owned(),
                revision: identity.revision(),
                digest,
            }
        })
        .collect();
    MeasuredMemberBinding {
        requested_game_id,
        result: MeasuredFoundMember {
            kind: "Found",
            game_id: detail.game_id().to_string(),
            lifecycle: "Active",
            content_identities,
        },
    }
}

fn hydration_facets(executor: &SqliteDatabaseExecutor) -> Vec<(HydrationState, u32)> {
    let query = LibraryFacetQuery::new(LibraryScope::All, None, LibraryFilter::empty())
        .expect("valid hydration facet query");
    executor
        .execute(&context("hydration_facets"), move |mut work| {
            let facets = {
                let mut logical = work.logical_content();
                logical.get_library_facets(&query)?
            };
            work.commit()?;
            Ok(facets
                .hydration_states()
                .iter()
                .map(|bucket| (bucket.hydration_state(), bucket.count()))
                .collect())
        })
        .expect("read hydration facets")
}

fn query_contract_version(executor: &SqliteDatabaseExecutor) -> i64 {
    executor
        .with_connection_for_tests(context("read_query_contract_version"), |connection| {
            connection.scalar_i64(
                "SELECT query_contract_version FROM library_view_state WHERE singleton_key = 1",
            )
        })
        .expect("read query-contract version")
}

fn generation(executor: &SqliteDatabaseExecutor) -> String {
    executor
        .with_connection_for_tests(context("read_generation"), |connection| {
            connection
                .scalar_text("SELECT generation_id FROM library_view_state WHERE singleton_key = 1")
        })
        .expect("read database generation")
}

fn revision(executor: &SqliteDatabaseExecutor) -> i64 {
    executor
        .with_connection_for_tests(context("read_revision"), |connection| {
            connection.scalar_i64(
                "SELECT membership_revision FROM library_view_state WHERE singleton_key = 1",
            )
        })
        .expect("read membership revision")
}

fn identity_membership_revision(executor: &SqliteDatabaseExecutor) -> i64 {
    executor
        .with_connection_for_tests(context("read_identity_membership_revision"), |connection| {
            connection.scalar_i64(
                "SELECT identity_membership_revision
                 FROM library_view_state WHERE singleton_key = 1",
            )
        })
        .expect("read identity membership revision")
}

fn write(executor: &SqliteDatabaseExecutor, sql: &'static str) {
    write_named(executor, "write", sql);
}

fn write_named(executor: &SqliteDatabaseExecutor, operation: &'static str, sql: &'static str) {
    executor
        .with_unit_of_work(context(operation), move |mut work| {
            work.execute_batch_for_tests(sql)
                .map_err(ApplicationPortError::Persistence)?;
            work.commit()?;
            Ok(())
        })
        .expect(operation);
}

#[test]
fn revision_advances_once_for_final_query_key_changes_and_never_for_noop_or_rollback() {
    let database = open();
    write(
        &database.executor,
        "INSERT INTO game (
            game_id, platform_id, lifecycle_state, grouping_revision, fallback_title,
            fallback_title_provenance, hydration_state, created_at, updated_at
         ) VALUES (
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'nintendo.gb', 'active', 1,
            'Alpha', 'local_fallback', 'partially_hydrated', '1', '1'
         );
         INSERT INTO game_library_row (
            game_id, display_title, display_title_provenance, platform_id,
            presentation_region, selected_cover_asset_id, release_date, search_text,
            hydration_state, availability_state, content_count, source_count, updated_at
         ) VALUES (
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Alpha', 'local_fallback', 'nintendo.gb',
            NULL, NULL, NULL, 'alpha', 'partially_hydrated', 'available', 0, 0, '1'
         );",
    );
    assert_eq!(revision(&database.executor), 2);
    assert_eq!(identity_membership_revision(&database.executor), 2);

    write(
        &database.executor,
        "UPDATE game_library_row SET display_title = display_title
         WHERE game_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';",
    );
    assert_eq!(
        revision(&database.executor),
        2,
        "same-value writes are semantic no-ops"
    );
    assert_eq!(identity_membership_revision(&database.executor), 2);

    write(
        &database.executor,
        "UPDATE game_library_row SET display_title = 'Temporary'
         WHERE game_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
         UPDATE game_library_row SET display_title = 'Alpha'
         WHERE game_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';",
    );
    assert_eq!(
        revision(&database.executor),
        2,
        "restoring the original keys is a no-op"
    );
    assert_eq!(identity_membership_revision(&database.executor), 2);

    write(
        &database.executor,
        "UPDATE game_library_row SET display_title = 'Beta', platform_id = 'nintendo.gbc',
             presentation_region = 'US', release_date = '1990-01-01', search_text = 'beta',
             hydration_state = 'hydrated', availability_state = 'partially_unavailable',
             updated_at = '2'
         WHERE game_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';",
    );
    assert_eq!(
        revision(&database.executor),
        3,
        "one transaction advances the revision once"
    );
    assert_eq!(identity_membership_revision(&database.executor), 3);

    write(
        &database.executor,
        "UPDATE game_library_row SET display_title = 'Gamma'
         WHERE game_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
         UPDATE game_library_row SET search_text = 'gamma', updated_at = '3'
         WHERE game_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';",
    );
    assert_eq!(
        revision(&database.executor),
        4,
        "combined updates still advance only once"
    );
    assert_eq!(identity_membership_revision(&database.executor), 4);

    database
        .executor
        .with_unit_of_work(context("rollback"), move |mut work| {
            work.execute_batch_for_tests(
                "UPDATE game_library_row SET display_title = 'Rolled back', updated_at = '4'
                 WHERE game_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';",
            )
            .map_err(ApplicationPortError::Persistence)?;
            work.rollback()?;
            Ok(())
        })
        .expect("rollback transaction");
    assert_eq!(
        revision(&database.executor),
        4,
        "rolled-back changes do not advance it"
    );
    assert_eq!(identity_membership_revision(&database.executor), 4);

    database.executor.shutdown().expect("close database");
}

#[test]
fn identity_membership_revision_migration_preserves_v1_state() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("library.sqlite3");
    let legacy_executor = SqliteDatabaseExecutor::open_with_registry(
        &path,
        MigrationRegistry::embedded_through_for_tests(20),
    )
    .expect("open schema v20 database");
    write(
        &legacy_executor,
        "UPDATE library_view_state SET membership_revision = 17 WHERE singleton_key = 1;",
    );
    legacy_executor
        .shutdown()
        .expect("close schema v20 database");

    let database = TestDatabase {
        _directory: directory,
        executor: SqliteDatabaseExecutor::open_with_capacity_and_view_key(
            path,
            DEFAULT_QUEUE_CAPACITY,
            [0x4d; 32],
        )
        .expect("upgrade schema v20 database"),
    };
    let revision_columns = database
        .executor
        .with_connection_for_tests(context("inspect_identity_revision_schema"), |connection| {
            connection.scalar_i64(
                "SELECT count(*) FROM pragma_table_info('library_view_state')
                 WHERE name = 'identity_membership_revision'",
            )
        })
        .expect("inspect Library view state schema");

    assert_eq!(
        revision_columns, 1,
        "the V2 fence needs a distinct persisted revision column"
    );
    assert_eq!(revision(&database.executor), 17);
    assert_eq!(identity_membership_revision(&database.executor), 1);
    database.executor.shutdown().expect("close database");
}

#[test]
fn projection_remove_restore_around_identity_noop_preserves_existing_views() {
    let database = open();
    insert_two_games_with_roots(&database.executor);

    let v1_page =
        fenced_list(&database.executor, list_query(None, 2, None), None).expect("create V1 view");
    let v1_token = v1_page.view_token().clone();
    let game_id = v1_page.page().items()[0].game_id();
    let v2_page = fenced_identity_list(&database.executor, list_query(None, 2, None), None)
        .expect("create V2 view");
    let v2_token = v2_page.view_token().clone();
    let v1_revision_before = revision(&database.executor);
    let v2_revision_before = identity_membership_revision(&database.executor);

    write(
        &database.executor,
        "CREATE TEMP TABLE saved_projection_for_identity_noop AS
             SELECT * FROM main.game_library_row
             WHERE game_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
         DELETE FROM main.game_library_row
         WHERE game_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
         UPDATE main.game_content
         SET identification_state = identification_state
         WHERE game_content_id = 'ffffffffffffffffffffffffffffffff';
         INSERT INTO main.game_library_row
         SELECT * FROM temp.saved_projection_for_identity_noop;
         DROP TABLE temp.saved_projection_for_identity_noop;",
    );

    assert_eq!(revision(&database.executor), v1_revision_before);
    assert_eq!(
        identity_membership_revision(&database.executor),
        v2_revision_before,
        "restoring the projection must preserve the V2 semantic view"
    );
    assert!(matches!(
        fenced_game(&database.executor, game_id, v1_token),
        Ok(GetGameResult::Found(_))
    ));
    assert!(matches!(
        fenced_identity_game(&database.executor, game_id, v2_token),
        Ok(GetGameResult::Found(_))
    ));

    database.executor.shutdown().expect("close database");
}

#[test]
fn identity_only_change_advances_v2_without_staling_v1_views() {
    let database = open();
    insert_two_games_with_roots(&database.executor);
    let page =
        fenced_list(&database.executor, list_query(None, 2, None), None).expect("create V1 view");
    let token = page.view_token().clone();
    let game_id = page.page().items()[0].game_id();
    let v2_page = fenced_identity_list(&database.executor, list_query(None, 2, None), None)
        .expect("create V2 view");
    let v2_token = v2_page.view_token().clone();
    let v1_revision_before = revision(&database.executor);
    let v2_revision_before = identity_membership_revision(&database.executor);

    write(
        &database.executor,
        "UPDATE game_content
         SET identification_state = 'identified'
         WHERE game_content_id = 'ffffffffffffffffffffffffffffffff';
         INSERT INTO content_identity (
             content_identity_id, game_content_id, scheme_id, identity_revision,
             identity_value, is_current, created_at, updated_at
         ) VALUES (
             '15151515151515151515151515151515',
             'ffffffffffffffffffffffffffffffff',
             'argus.content.identity.nintendo-gb.cartridge.v1',
             1,
             '0909090909090909090909090909090909090909090909090909090909090909',
             1,
             '1',
             '1'
         );",
    );

    assert_eq!(
        identity_membership_revision(&database.executor),
        v2_revision_before + 1
    );
    assert_eq!(revision(&database.executor), v1_revision_before);
    assert!(matches!(
        fenced_game(&database.executor, game_id, token.clone()),
        Ok(GetGameResult::Found(_))
    ));
    assert!(matches!(
        fenced_identity_game(&database.executor, game_id, v2_token),
        Err(ApplicationPortError::LibraryViewStale)
    ));

    let v2_page = fenced_identity_list(&database.executor, list_query(None, 2, None), None)
        .expect("create V2 view after identification");
    let v2_token = v2_page.view_token().clone();
    write(
        &database.executor,
        "UPDATE content_identity
         SET identity_value = '0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a'
         WHERE content_identity_id = '15151515151515151515151515151515';",
    );

    assert_eq!(
        identity_membership_revision(&database.executor),
        v2_revision_before + 2
    );
    assert_eq!(revision(&database.executor), v1_revision_before);
    assert!(matches!(
        fenced_game(&database.executor, game_id, token.clone()),
        Ok(GetGameResult::Found(_))
    ));
    assert!(matches!(
        fenced_identity_game(&database.executor, game_id, v2_token),
        Err(ApplicationPortError::LibraryViewStale)
    ));

    let v2_page = fenced_identity_list(&database.executor, list_query(None, 2, None), None)
        .expect("create V2 view before currentness change");
    let v2_token = v2_page.view_token().clone();
    write(
        &database.executor,
        "UPDATE content_identity SET is_current = 0
         WHERE content_identity_id = '15151515151515151515151515151515';",
    );
    assert_eq!(
        identity_membership_revision(&database.executor),
        v2_revision_before + 3
    );
    assert_eq!(revision(&database.executor), v1_revision_before);
    assert!(matches!(
        fenced_game(&database.executor, game_id, token),
        Ok(GetGameResult::Found(_))
    ));
    assert!(matches!(
        fenced_identity_game(&database.executor, game_id, v2_token),
        Err(ApplicationPortError::LibraryViewStale)
    ));
    database.executor.shutdown().expect("close database");
}

#[test]
fn observer_v2_membership_cancellation_interrupts_an_actual_read() {
    let database = open();
    seed_identity_membership_fixture(&database.executor);

    let cancellation = ObserverCancellationHandle::new();
    let hook_fired = Arc::new(AtomicBool::new(false));
    let (entered_sender, entered_receiver) = mpsc::sync_channel(1);
    let entered_sender = Arc::new(Mutex::new(Some(entered_sender)));
    let release = Arc::new(Barrier::new(2));
    let hook_fired_once = Arc::clone(&hook_fired);
    let hook_sender = Arc::clone(&entered_sender);
    let hook_release = Arc::clone(&release);
    cancellation.with_progress_hook_for_tests(move || {
        if !hook_fired_once.swap(true, Ordering::AcqRel) {
            if let Ok(mut sender) = hook_sender.lock()
                && let Some(sender) = sender.take()
            {
                let _ = sender.send(());
            }
            hook_release.wait();
        }
    });

    let worker_executor = database.executor.clone();
    let worker_cancellation = cancellation.clone();
    let worker = thread::spawn(move || {
        observer_identity_list(
            &worker_executor,
            list_query(None, 1, None),
            None,
            worker_cancellation,
        )
    });
    entered_receiver
        .recv_timeout(Duration::from_secs(5))
        .expect("SQLite progress hook runs during the V2 membership read");
    assert!(cancellation.cancel().expect("cancel active V2 read"));
    release.wait();
    assert!(matches!(
        worker.join().expect("V2 membership reader thread"),
        Err(SqliteExecutorError::ObserverCancelled)
    ));

    let value = database
        .executor
        .with_connection_for_tests(context("ordinary_after_v2_cancel"), |connection| {
            connection.scalar_i64("SELECT 44")
        })
        .expect("ordinary query after V2 interrupt retirement");
    assert_eq!(value, 44);
    database.executor.shutdown().expect("close database");
}

#[test]
fn observer_v2_membership_cancellation_discards_partial_result_assembly() {
    let database = open();
    seed_identity_membership_fixture(&database.executor);

    let cancellation = ObserverCancellationHandle::new();
    let (entered_sender, entered_receiver) = mpsc::sync_channel(1);
    let (release_sender, release_receiver) = mpsc::sync_channel(1);
    let worker_executor = database.executor.clone();
    let worker_cancellation = cancellation.clone();
    let callback_cancellation = worker_cancellation.clone();
    let worker = thread::spawn(move || {
        worker_executor.with_observer_unit_of_work_for_tests(
            context("observer_v2_membership_assembly"),
            worker_cancellation,
            move |mut work| {
                let mut logical = work.logical_content();
                let first = logical
                    .list_games_identity_revision_fenced(&list_query(None, 1, None), None)?;
                let token = first.view_token().clone();
                let mut pages = vec![first];
                while let Some(cursor) = pages
                    .last()
                    .expect("first V2 page exists")
                    .page()
                    .next_cursor()
                    .cloned()
                {
                    pages.push(logical.list_games_identity_revision_fenced(
                        &list_query(Some(cursor), 1, None),
                        Some(&token),
                    )?);
                }
                assert_eq!(pages.len(), 2, "fixture has a complete two-page chain");

                let game_ids = pages
                    .iter()
                    .flat_map(|page| page.page().items())
                    .map(|game| game.game_id())
                    .collect::<Vec<_>>();
                let mut member_bindings = Vec::with_capacity(game_ids.len());
                for game_id in game_ids {
                    let requested_game_id = game_id.to_string();
                    let result = logical.get_game_identity_revision_fenced(game_id, &token)?;
                    member_bindings.push(measured_member_binding(requested_game_id, result));
                    if member_bindings.len() == 1 {
                        entered_sender
                            .send(())
                            .expect("test is waiting for partial membership assembly");
                        let _ = release_receiver.recv_timeout(Duration::from_secs(5));
                    }
                    if callback_cancellation.is_cancelled_for_tests() {
                        return Ok(member_bindings);
                    }
                }
                Ok(member_bindings)
            },
        )
    });

    entered_receiver
        .recv_timeout(Duration::from_secs(5))
        .expect("first same-token member is assembled inside observer scope");
    assert!(cancellation.cancel().expect("cancel member assembly"));
    release_sender.send(()).expect("release observer callback");
    assert!(matches!(
        worker.join().expect("V2 membership assembler thread"),
        Err(SqliteExecutorError::ObserverCancelled)
    ));

    let value = database
        .executor
        .with_connection_for_tests(context("ordinary_after_v2_assembly_cancel"), |connection| {
            connection.scalar_i64("SELECT 45")
        })
        .expect("ordinary query after assembly cancellation");
    assert_eq!(value, 45);
    database.executor.shutdown().expect("close database");
}

#[test]
fn observer_scoped_v2_reads_complete_page_chain_and_same_view_lookups() {
    let database = open();
    seed_identity_membership_fixture(&database.executor);

    let first = observer_identity_list(
        &database.executor,
        list_query(None, 1, None),
        None,
        ObserverCancellationHandle::new(),
    )
    .expect("first observer V2 page");
    let token = first.view_token().clone();
    let identity_revision = first.identity_membership_revision();
    let query_contract_version = first.query_contract_version();
    let mut pages = vec![first];
    while let Some(cursor) = pages
        .last()
        .expect("at least one page")
        .page()
        .next_cursor()
        .cloned()
    {
        let page = observer_identity_list(
            &database.executor,
            list_query(Some(cursor), 1, None),
            Some(token.clone()),
            ObserverCancellationHandle::new(),
        )
        .expect("continue the same observer V2 view");
        assert_eq!(page.view_token(), &token);
        assert_eq!(page.identity_membership_revision(), identity_revision);
        assert_eq!(page.query_contract_version(), query_contract_version);
        pages.push(page);
    }

    let game_ids = pages
        .iter()
        .flat_map(|page| page.page().items())
        .map(|game| game.game_id().to_string())
        .collect::<Vec<_>>();
    assert_eq!(
        pages.len(),
        2,
        "the fixture forms a complete two-page chain"
    );
    assert_eq!(
        game_ids,
        [
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_owned(),
            "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_owned(),
        ]
    );

    let mut member_identity_bindings = Vec::with_capacity(game_ids.len());
    for game_id in &game_ids {
        let requested_game_id = game_id.clone();
        let game_id = argus_domain::GameId::try_from(game_id.as_str()).expect("GameId");
        let result = observer_identity_game(
            &database.executor,
            game_id,
            token.clone(),
            ObserverCancellationHandle::new(),
        )
        .expect("same-token member lookup");
        let binding = measured_member_binding(requested_game_id, result);
        assert_eq!(binding.result.content_identities.len(), 1);
        member_identity_bindings.push(binding);
    }

    let absent_prior_game_id = "cccccccccccccccccccccccccccccccc";
    let absent_prior_id = argus_domain::GameId::try_from(absent_prior_game_id).expect("GameId");
    assert_eq!(
        observer_identity_game(
            &database.executor,
            absent_prior_id,
            token.clone(),
            ObserverCancellationHandle::new(),
        )
        .expect("complete same-view absent prior-ID lookup"),
        GetGameResult::NotFound,
        "GameNotFound is a complete lookup result, not missing evidence"
    );

    let membership_result = MeasuredMembershipResult {
        query: "AllActiveDisplayTitleAscendingV1",
        page_size: 1,
        page_count: pages.len() as u64,
        identity_membership_revision: identity_revision,
        identity_view_contract_version: 2,
        query_contract_version,
        game_ids: game_ids.clone(),
        member_identity_bindings,
        prior_lookups: vec![MeasuredPriorLookup {
            requested_game_id: absent_prior_game_id.to_owned(),
            result: MeasuredGameNotFound {
                kind: "GameNotFound",
                application_error: MeasuredApplicationError {
                    code: "ARGUS.V1.CONFIGURATION.GAME_NOT_FOUND",
                    category: "configuration",
                    severity: "Warning",
                    recoverability: "UserAction",
                    retry_policy: "Never",
                    message_key: "errors.library.game_not_found",
                    trace_id: "0000000000000000000000000000001c",
                    safe_context: Vec::new(),
                },
            },
        }],
    };
    let response_body = observer_v1::serialize_observer_success_response_v1_for_tests(
        &membership_result,
        "00000000000000000000000000000004",
        "00000000000000000000000000000005",
        "00000000000000000000000000000006",
        500,
        520,
    )
    .expect("serialize complete observer membership response");
    let framed_response = observer_v1::frame_observer_response_v1_for_tests(&response_body)
        .expect("frame complete observer membership response");
    assert_eq!(framed_response.len(), response_body.len() + 4);
    assert_eq!(
        u32::from_be_bytes(
            framed_response[..4]
                .try_into()
                .expect("four-byte response prefix")
        ) as usize,
        response_body.len()
    );
    let response_text = std::str::from_utf8(&response_body).expect("UTF-8 response body");
    assert!(response_text.starts_with(
        r#"{"protocol_id":"argus.product-observer","protocol_version":1,"request_id":"00000000000000000000000000000004","connection_id":"00000000000000000000000000000005","attempt_id":"00000000000000000000000000000006","outcome":{"kind":"CompleteSuccess","result":{"query":"AllActiveDisplayTitleAscendingV1","pageSize":1"#
    ));
    let response_json: serde_json::Value =
        serde_json::from_slice(&response_body).expect("valid measured response");
    let object_keys = |value: &serde_json::Value| {
        value
            .as_object()
            .expect("JSON object")
            .keys()
            .cloned()
            .collect::<std::collections::BTreeSet<_>>()
    };
    assert_eq!(
        object_keys(&response_json),
        std::collections::BTreeSet::from([
            "protocol_id".to_owned(),
            "protocol_version".to_owned(),
            "request_id".to_owned(),
            "connection_id".to_owned(),
            "attempt_id".to_owned(),
            "outcome".to_owned(),
            "observer_started_elapsed_realtime_ms".to_owned(),
            "observer_finished_elapsed_realtime_ms".to_owned(),
        ])
    );
    assert_eq!(
        object_keys(&response_json["outcome"]),
        std::collections::BTreeSet::from(["kind".to_owned(), "result".to_owned()])
    );
    assert_eq!(
        object_keys(&response_json["outcome"]["result"]),
        std::collections::BTreeSet::from([
            "query".to_owned(),
            "pageSize".to_owned(),
            "pageCount".to_owned(),
            "identityMembershipRevision".to_owned(),
            "identityViewContractVersion".to_owned(),
            "queryContractVersion".to_owned(),
            "gameIds".to_owned(),
            "memberIdentityBindings".to_owned(),
            "priorLookups".to_owned(),
        ])
    );
    assert_eq!(
        response_json["outcome"]["result"]["gameIds"]
            .as_array()
            .expect("complete GameId set")
            .len(),
        game_ids.len()
    );
    assert_eq!(
        response_json["outcome"]["result"]["priorLookups"][0]["result"]["kind"],
        "GameNotFound"
    );
    assert_eq!(
        object_keys(&response_json["outcome"]["result"]["memberIdentityBindings"][0]),
        std::collections::BTreeSet::from(["requestedGameId".to_owned(), "result".to_owned(),])
    );
    assert_eq!(
        object_keys(&response_json["outcome"]["result"]["memberIdentityBindings"][0]["result"]),
        std::collections::BTreeSet::from([
            "kind".to_owned(),
            "gameId".to_owned(),
            "lifecycle".to_owned(),
            "contentIdentities".to_owned(),
        ])
    );
    assert_eq!(
        object_keys(
            &response_json["outcome"]["result"]["memberIdentityBindings"][0]["result"]["contentIdentities"]
                [0]
        ),
        std::collections::BTreeSet::from([
            "platformId".to_owned(),
            "contentType".to_owned(),
            "schemeId".to_owned(),
            "revision".to_owned(),
            "digest".to_owned(),
        ])
    );
    assert_eq!(
        object_keys(&response_json["outcome"]["result"]["priorLookups"][0]),
        std::collections::BTreeSet::from(["requestedGameId".to_owned(), "result".to_owned(),])
    );
    assert_eq!(
        object_keys(&response_json["outcome"]["result"]["priorLookups"][0]["result"]),
        std::collections::BTreeSet::from(["kind".to_owned(), "applicationError".to_owned(),])
    );
    assert_eq!(
        object_keys(
            &response_json["outcome"]["result"]["priorLookups"][0]["result"]["applicationError"]
        ),
        std::collections::BTreeSet::from([
            "code".to_owned(),
            "category".to_owned(),
            "severity".to_owned(),
            "recoverability".to_owned(),
            "retryPolicy".to_owned(),
            "messageKey".to_owned(),
            "traceId".to_owned(),
            "safeContext".to_owned(),
        ])
    );
    eprintln!(
        "host_membership_games={} host_membership_pages={} host_page_size=1 host_prior_lookups=1 host_response_json_bytes={} host_framed_bytes={}",
        game_ids.len(),
        pages.len(),
        response_body.len(),
        framed_response.len()
    );

    write(
        &database.executor,
        "UPDATE content_identity
         SET identity_value = '0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b'
         WHERE content_identity_id = '15151515151515151515151515151515';",
    );
    let stale_member_id = argus_domain::GameId::try_from(game_ids[0].as_str()).expect("GameId");
    assert!(
        matches!(
            observer_identity_game(
                &database.executor,
                stale_member_id,
                token,
                ObserverCancellationHandle::new(),
            ),
            Err(SqliteExecutorError::ApplicationCallback(
                ApplicationPortError::LibraryViewStale
            ))
        ),
        "a stale token is incomplete evidence and must not become a lookup result"
    );

    database.executor.shutdown().expect("close database");
}

#[test]
fn identity_revision_overflow_rejects_identity_write_without_staling_v1_view() {
    let database = open();
    insert_two_games_with_roots(&database.executor);
    write(
        &database.executor,
        "UPDATE game_content
         SET identification_state = 'identified'
         WHERE game_content_id = 'ffffffffffffffffffffffffffffffff';
         INSERT INTO content_identity (
             content_identity_id, game_content_id, scheme_id, identity_revision,
             identity_value, is_current, created_at, updated_at
         ) VALUES (
             '15151515151515151515151515151515',
             'ffffffffffffffffffffffffffffffff',
             'argus.content.identity.nintendo-gb.cartridge.v1',
             1,
             '0909090909090909090909090909090909090909090909090909090909090909',
             1,
             '1',
             '1'
         );",
    );
    let page =
        fenced_list(&database.executor, list_query(None, 2, None), None).expect("create V1 view");
    let token = page.view_token().clone();
    let game_id = page.page().items()[0].game_id();
    let v1_revision_before = revision(&database.executor);

    write(
        &database.executor,
        "UPDATE library_view_state SET identity_membership_revision = 9223372036854775807
         WHERE singleton_key = 1;",
    );
    let result = database
        .executor
        .execute(&context("overflow_identity_write"), |mut work| {
            work.execute_batch_for_tests(
                "UPDATE content_identity
             SET identity_value = '0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a'
             WHERE content_identity_id = '15151515151515151515151515151515';",
            )
            .map_err(ApplicationPortError::Persistence)?;
            work.commit()?;
            Ok(())
        });

    assert!(matches!(
        result,
        Err(ApplicationPortError::Persistence(
            PersistenceError::Internal
        ))
    ));
    assert_eq!(revision(&database.executor), v1_revision_before);
    assert_eq!(identity_membership_revision(&database.executor), i64::MAX);
    assert!(matches!(
        fenced_game(&database.executor, game_id, token),
        Ok(GetGameResult::Found(_))
    ));
    database.executor.shutdown().expect("close database");
}

#[test]
fn identity_view_v2_fences_pages_and_details_with_a_distinct_token() {
    let database = open();
    insert_two_games_with_roots(&database.executor);

    let first = fenced_identity_list(&database.executor, list_query(None, 1, None), None)
        .expect("create V2 identity view");
    let token = first.view_token().clone();
    assert!(token.as_str().starts_with("lvt2:"));
    assert_eq!(
        first.identity_membership_revision(),
        identity_membership_revision(&database.executor)
    );
    let first_game_id = first.page().items()[0].game_id();
    let cursor = first
        .page()
        .next_cursor()
        .cloned()
        .expect("first page has a continuation");

    let next = fenced_identity_list(
        &database.executor,
        list_query(Some(cursor), 1, None),
        Some(token.clone()),
    )
    .expect("continue the V2 identity view");
    assert_eq!(next.view_token(), &token);
    assert_eq!(
        next.identity_membership_revision(),
        first.identity_membership_revision()
    );
    assert!(matches!(
        fenced_identity_game(&database.executor, first_game_id, token.clone()),
        Ok(GetGameResult::Found(_))
    ));

    let v1 =
        fenced_list(&database.executor, list_query(None, 1, None), None).expect("create V1 view");
    let v1_value_as_v2 =
        LibraryIdentityViewTokenV2::try_from_external(v1.view_token().as_str().to_owned())
            .expect("token wrapper accepts bounded opaque values");
    assert!(matches!(
        fenced_identity_game(&database.executor, first_game_id, v1_value_as_v2),
        Err(ApplicationPortError::LibraryViewTokenInvalid)
    ));
    database.executor.shutdown().expect("close database");
}

#[test]
fn identity_view_v2_rejects_query_shapes_outside_its_fixed_contract() {
    let database = open();
    let query = list_query(None, 10, Some("mario"));

    assert!(matches!(
        fenced_identity_list(&database.executor, query, None),
        Err(ApplicationPortError::LibraryViewTokenInvalid)
    ));
    database.executor.shutdown().expect("close database");
}

#[test]
fn response_only_projection_fields_do_not_advance_query_revision() {
    let database = open();
    write(
        &database.executor,
        "INSERT INTO game (
            game_id, platform_id, lifecycle_state, grouping_revision, fallback_title,
            fallback_title_provenance, hydration_state, created_at, updated_at
         ) VALUES (
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'nintendo.gb', 'active', 1,
            'Alpha', 'local_fallback', 'partially_hydrated', '1', '1'
         );
         INSERT INTO game_library_row (
            game_id, display_title, display_title_provenance, platform_id,
            presentation_region, selected_cover_asset_id, release_date, search_text,
            hydration_state, availability_state, content_count, source_count, updated_at
         ) VALUES (
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Alpha', 'local_fallback', 'nintendo.gb',
            NULL, NULL, NULL, 'alpha', 'partially_hydrated', 'available', 0, 0, '1'
         );",
    );
    let initial_revision = revision(&database.executor);

    write(
        &database.executor,
        "UPDATE game_library_row SET content_count = 4, source_count = 3
         WHERE game_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';",
    );
    assert_eq!(revision(&database.executor), initial_revision);
    database.executor.shutdown().expect("close database");
}

#[test]
fn source_relationships_and_indirect_root_availability_refresh_advance_revision() {
    let database = open();
    write_named(
        &database.executor,
        "insert_library_source",
        "INSERT INTO library_source (
            library_source_id, source_provider_type, display_name, provider_config,
            config_revision, created_at, updated_at
         ) VALUES (
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'local_filesystem', 'Test source',
            '{}', 1, '1', '1'
         );",
    );
    write_named(
        &database.executor,
        "insert_library_roots",
        "INSERT INTO library_root (
            library_root_id, library_source_id, root_locator, display_name,
            safe_location_presentation, availability_status, config_revision,
            created_at, updated_at
         ) VALUES
            ('cccccccccccccccccccccccccccccccc', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
             'root-a', 'Root A', 'Root A', 'available', 1, '1', '1'),
            ('dddddddddddddddddddddddddddddddd', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
             'root-b', 'Root B', 'Root B', 'available', 1, '1', '1');",
    );
    write_named(
        &database.executor,
        "insert_source_entry",
        "INSERT INTO source_entry (
            source_entry_id, library_root_id, parent_source_entry_id, coordinate_kind,
            relative_locator, locator_key, display_name, display_location, kind,
            classification, provider_native_identity, source_fingerprint,
            derived_locator, derived_entry_key, derived_fingerprint,
            derivation_transformation_id, derivation_revision,
            last_observed_scan_id, created_at, updated_at
         ) VALUES (
            'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee', 'cccccccccccccccccccccccccccccccc',
            NULL, 'provider', 'game.gb', 'game.gb', 'game.gb', 'game.gb', 'file',
            'content_candidate', NULL, NULL, NULL, NULL, NULL, NULL, NULL, '', 1, 1
         );",
    );
    write_named(
        &database.executor,
        "insert_game_content",
        "INSERT INTO game_content (
            game_content_id, platform_id, content_type, presence_state,
            identification_state, grouping_revision, created_at, updated_at
         ) VALUES (
            'ffffffffffffffffffffffffffffffff', 'nintendo.gb', 'CartridgeImage',
            'available', 'unidentified', 1, '1', '1'
         );",
    );
    write_named(
        &database.executor,
        "insert_game_content_source",
        "INSERT INTO game_content_source (
            game_content_source_id, game_content_id, source_entry_id,
            association_key, source_fingerprint, last_observed_scan_id,
            is_current, created_at, updated_at
         ) VALUES (
            '11111111111111111111111111111111',
            'ffffffffffffffffffffffffffffffff', 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
            'primary', NULL, NULL, 1, '1', '1'
         );",
    );
    write_named(
        &database.executor,
        "insert_game",
        "INSERT INTO game (
            game_id, platform_id, lifecycle_state, grouping_revision, fallback_title,
            fallback_title_provenance, hydration_state, created_at, updated_at
         ) VALUES (
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'nintendo.gb', 'active', 1,
            'Alpha', 'local_fallback', 'partially_hydrated', '1', '1'
         );",
    );
    write_named(
        &database.executor,
        "insert_membership",
        "INSERT INTO game_membership (
            game_membership_id, game_id, game_content_id, relationship,
            grouping_basis, grouping_revision, is_current, created_at, updated_at
         ) VALUES (
            '22222222222222222222222222222222',
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            'ffffffffffffffffffffffffffffffff', 'primary_content', 'provisional', 1, 1, '1', '1'
         );",
    );
    write_named(
        &database.executor,
        "insert_library_projection",
        "INSERT INTO game_library_row (
            game_id, display_title, display_title_provenance, platform_id,
            presentation_region, selected_cover_asset_id, release_date, search_text,
            hydration_state, availability_state, content_count, source_count, updated_at
         ) VALUES (
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Alpha', 'local_fallback', 'nintendo.gb',
            NULL, NULL, NULL, 'alpha', 'partially_hydrated', 'available', 1, 1, '1'
         );",
    );
    let initial_revision = revision(&database.executor);

    let root_id =
        LibraryRootId::try_from("cccccccccccccccccccccccccccccccc").expect("root identity");
    database
        .executor
        .with_unit_of_work(context("availability"), move |mut work| {
            assert!(
                work.library_roots()
                    .set_availability(root_id, LibraryRootAvailability::Unavailable)?
            );
            work.commit()?;
            Ok(())
        })
        .expect("commit root availability and its indirect projection refresh");
    assert_eq!(revision(&database.executor), initial_revision + 1);

    write(
        &database.executor,
        "UPDATE source_entry
         SET library_root_id = 'dddddddddddddddddddddddddddddddd'
         WHERE source_entry_id = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';",
    );
    assert_eq!(revision(&database.executor), initial_revision + 2);

    write(
        &database.executor,
        "UPDATE game_membership SET relationship = 'regional_variant'
         WHERE game_membership_id = '22222222222222222222222222222222';",
    );
    assert_eq!(revision(&database.executor), initial_revision + 3);
    database.executor.shutdown().expect("close database");
}

#[test]
fn active_game_and_resolution_refreshes_change_only_effective_hydration_keys() {
    let database = open();
    insert_two_games(&database.executor);
    let initial_revision = revision(&database.executor);

    write(
        &database.executor,
        "INSERT INTO job_run (
            job_run_id, operation_type, state, created_at, queued_at
         ) VALUES (
            '88888888888888888888888888888888', 'game_refresh', 'queued', 1, 1
         );
         INSERT INTO game_refresh_intent (job_run_id, game_ids, mode)
         VALUES (
            '88888888888888888888888888888888',
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'eligible_only'
         );
         UPDATE game_library_row
         SET hydration_state = 'hydrated', updated_at = '1970-01-01T00:00:02Z'
         WHERE game_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';",
    );
    assert_eq!(revision(&database.executor), initial_revision + 1);

    let first = fenced_list(&database.executor, list_query(None, 10, None), None)
        .expect("read overlay for active game refresh");
    let detail = fenced_game(
        &database.executor,
        argus_domain::GameId::try_from("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa").expect("game identity"),
        first.view_token().clone(),
    )
    .expect("read active-refresh Game detail");
    let GetGameResult::Found(detail) = detail else {
        panic!("active Game must remain addressable");
    };
    assert_eq!(detail.hydration_state(), HydrationState::Refreshing);
    let rows = first.page().items();
    assert_eq!(rows.len(), 2);
    assert_eq!(rows[0].hydration_state(), HydrationState::Refreshing);
    assert_eq!(rows[0].updated_at_ms(), 2_000);
    assert_eq!(rows[1].hydration_state(), HydrationState::PartiallyHydrated);
    let facets = hydration_facets(&database.executor);
    assert!(facets.contains(&(HydrationState::Refreshing, 1)));
    assert!(facets.contains(&(HydrationState::PartiallyHydrated, 1)));

    let refreshing_filter = LibraryFilter::new(
        Vec::new(),
        Vec::new(),
        vec![HydrationState::Refreshing],
        Vec::new(),
    )
    .expect("valid refreshing filter");
    let filtered_query = ListGamesQuery::builder()
        .scope(LibraryScope::All)
        .filters(refreshing_filter)
        .sort(LibrarySort::DisplayTitleAscending)
        .page_size(10)
        .build()
        .expect("valid refreshing list query");
    let filtered = fenced_list(&database.executor, filtered_query, None)
        .expect("filter by effective refreshing state");
    assert_eq!(filtered.page().items().len(), 1);
    assert_eq!(
        filtered.page().items()[0].game_id().to_string(),
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    );

    write(
        &database.executor,
        "UPDATE job_run
         SET state = 'running', started_at = 1, status_key = 'refreshing',
             completed_units = 1, total_units = 2
         WHERE job_run_id = '88888888888888888888888888888888';",
    );
    assert_eq!(revision(&database.executor), initial_revision + 1);
    let running = fenced_list(&database.executor, list_query(None, 10, None), None)
        .expect("running transition keeps refreshing query key");
    assert_eq!(running.page().items()[0].updated_at_ms(), 2_000);

    write(
        &database.executor,
        "INSERT INTO job_run (
            job_run_id, operation_type, state, created_at, queued_at
         ) VALUES (
            '77777777777777777777777777777777', 'game_refresh', 'queued', 1, 1
         );
         INSERT INTO game_refresh_intent (job_run_id, game_ids, mode)
         VALUES (
            '77777777777777777777777777777777',
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'eligible_only'
         );",
    );
    assert_eq!(revision(&database.executor), initial_revision + 1);

    write(
        &database.executor,
        "UPDATE job_run SET state = 'completed', completed_at = 3
         WHERE job_run_id = '88888888888888888888888888888888';",
    );
    assert_eq!(
        revision(&database.executor),
        initial_revision + 1,
        "one remaining active target keeps the same effective key"
    );
    write(
        &database.executor,
        "UPDATE job_run SET state = 'completed', completed_at = 4
         WHERE job_run_id = '77777777777777777777777777777777';",
    );
    assert_eq!(revision(&database.executor), initial_revision + 2);
    let completed = fenced_list(&database.executor, list_query(None, 10, None), None)
        .expect("terminal jobs restore persisted hydration values");
    let completed_detail = fenced_game(
        &database.executor,
        argus_domain::GameId::try_from("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa").expect("game identity"),
        completed.view_token().clone(),
    )
    .expect("read completed Game detail");
    let GetGameResult::Found(completed_detail) = completed_detail else {
        panic!("completed Game must remain addressable");
    };
    assert_eq!(completed_detail.hydration_state(), HydrationState::Hydrated);
    assert_eq!(
        completed.page().items()[0].hydration_state(),
        HydrationState::Hydrated
    );
    assert_eq!(completed.page().items()[0].updated_at_ms(), 2_000);
    assert!(hydration_facets(&database.executor).contains(&(HydrationState::Hydrated, 1)));

    write(
        &database.executor,
        "INSERT INTO job_run (
            job_run_id, operation_type, state, created_at, queued_at
         ) VALUES (
            '66666666666666666666666666666666',
            'library_resolution_refresh', 'queued', 1, 1
         );
         INSERT INTO library_resolution_refresh_intent (job_run_id, settings_revision)
         VALUES ('66666666666666666666666666666666', 1);",
    );
    assert_eq!(revision(&database.executor), initial_revision + 3);
    let resolution = fenced_list(&database.executor, list_query(None, 10, None), None)
        .expect("resolution refresh targets current Library games");
    assert!(
        resolution
            .page()
            .items()
            .iter()
            .all(|row| row.hydration_state() == HydrationState::Refreshing)
    );

    write(
        &database.executor,
        "UPDATE job_run SET state = 'running', started_at = 5
         WHERE job_run_id = '66666666666666666666666666666666';",
    );
    assert_eq!(revision(&database.executor), initial_revision + 3);
    write(
        &database.executor,
        "UPDATE job_run SET state = 'completed', completed_at = 6
         WHERE job_run_id = '66666666666666666666666666666666';",
    );
    assert_eq!(revision(&database.executor), initial_revision + 4);
    database.executor.shutdown().expect("close database");
}

#[test]
fn library_refresh_intent_tracks_only_games_in_its_current_root_scope() {
    let database = open();
    insert_two_games_with_roots(&database.executor);
    let initial_revision = revision(&database.executor);

    write(
        &database.executor,
        "INSERT INTO job_run (
            job_run_id, operation_type, state, created_at, queued_at,
            library_refresh_scope_version
         ) VALUES (
            '88888888888888888888888888888888', 'library_refresh', 'queued', 1, 1, 1
         );
         INSERT INTO library_refresh_intent (
            job_run_id, trigger_kind, trigger_root_id, mode, requested_root_ids_json
         ) VALUES (
            '88888888888888888888888888888888', 'manual', NULL, 'force',
            '[\"cccccccccccccccccccccccccccccccc\"]'
         );",
    );
    assert_eq!(revision(&database.executor), initial_revision + 1);
    let root_a = fenced_list(&database.executor, list_query(None, 10, None), None)
        .expect("root A refresh overlay");
    assert_eq!(
        root_a.page().items()[0].hydration_state(),
        HydrationState::Refreshing
    );
    assert_eq!(
        root_a.page().items()[1].hydration_state(),
        HydrationState::PartiallyHydrated
    );

    write(
        &database.executor,
        "INSERT INTO job_run (
            job_run_id, operation_type, state, created_at, queued_at,
            library_refresh_scope_version
         ) VALUES (
            '77777777777777777777777777777777', 'library_refresh', 'queued', 1, 1, 1
         );
         INSERT INTO library_refresh_intent (
            job_run_id, trigger_kind, trigger_root_id, mode, requested_root_ids_json
         ) VALUES (
            '77777777777777777777777777777777', 'manual', NULL, 'force',
            '[\"dddddddddddddddddddddddddddddddd\"]'
         );",
    );
    assert_eq!(revision(&database.executor), initial_revision + 2);
    let both_roots = fenced_list(&database.executor, list_query(None, 10, None), None)
        .expect("independent root refresh intents cover their current games");
    assert!(
        both_roots
            .page()
            .items()
            .iter()
            .all(|row| row.hydration_state() == HydrationState::Refreshing)
    );

    write(
        &database.executor,
        "UPDATE job_run SET state = 'running', started_at = 2
         WHERE job_run_id = '88888888888888888888888888888888';",
    );
    assert_eq!(revision(&database.executor), initial_revision + 2);
    write(
        &database.executor,
        "UPDATE job_run SET state = 'completed', completed_at = 3
         WHERE job_run_id = '88888888888888888888888888888888';",
    );
    assert_eq!(revision(&database.executor), initial_revision + 3);
    let root_b_only = fenced_list(&database.executor, list_query(None, 10, None), None)
        .expect("first terminal transition leaves the second root refreshing");
    assert_eq!(
        root_b_only.page().items()[0].hydration_state(),
        HydrationState::PartiallyHydrated
    );
    assert_eq!(
        root_b_only.page().items()[1].hydration_state(),
        HydrationState::Refreshing
    );
    write(
        &database.executor,
        "UPDATE job_run SET state = 'completed', completed_at = 4
         WHERE job_run_id = '77777777777777777777777777777777';",
    );
    assert_eq!(revision(&database.executor), initial_revision + 4);
    let completed = fenced_list(&database.executor, list_query(None, 10, None), None)
        .expect("terminal library refreshes remove the hydration overlays");
    assert!(
        completed
            .page()
            .items()
            .iter()
            .all(|row| row.hydration_state() == HydrationState::PartiallyHydrated)
    );
    database.executor.shutdown().expect("close database");
}

#[test]
fn library_refresh_terminal_transition_handles_repeated_game_sources() {
    let database = open();
    insert_two_games_with_roots(&database.executor);
    let initial_revision = revision(&database.executor);

    write(
        &database.executor,
        "INSERT INTO source_entry (
            source_entry_id, library_root_id, parent_source_entry_id, coordinate_kind,
            relative_locator, locator_key, display_name, display_location, kind,
            classification, provider_native_identity, source_fingerprint,
            derived_locator, derived_entry_key, derived_fingerprint,
            derivation_transformation_id, derivation_revision,
            last_observed_scan_id, created_at, updated_at
        ) VALUES (
            '15151515151515151515151515151515',
            'cccccccccccccccccccccccccccccccc', NULL, 'provider',
            'duplicate.gb', 'duplicate.gb', 'duplicate.gb', 'duplicate.gb',
            'file', 'content_candidate', NULL, NULL, NULL, NULL, NULL, NULL, NULL,
            '', 1, 1
        );
        INSERT INTO game_content_source (
            game_content_source_id, game_content_id, source_entry_id,
            association_key, source_fingerprint, last_observed_scan_id,
            is_current, created_at, updated_at
        ) VALUES (
            '16161616161616161616161616161616',
            'ffffffffffffffffffffffffffffffff',
            '15151515151515151515151515151515',
            'secondary', NULL, NULL, 1, '1', '1'
        );",
    );
    assert_eq!(revision(&database.executor), initial_revision + 1);

    write(
        &database.executor,
        "INSERT INTO job_run (
            job_run_id, operation_type, state, created_at, queued_at,
            library_refresh_scope_version
        ) VALUES (
            '17171717171717171717171717171717', 'library_refresh', 'queued', 2, 2, 1
        );
        INSERT INTO library_refresh_intent (
            job_run_id, trigger_kind, trigger_root_id, mode, requested_root_ids_json
        ) VALUES (
            '17171717171717171717171717171717', 'manual', NULL, 'force',
            '[\"cccccccccccccccccccccccccccccccc\"]'
        );",
    );
    assert_eq!(revision(&database.executor), initial_revision + 2);
    let active = fenced_list(&database.executor, list_query(None, 10, None), None)
        .expect("root refresh applies refreshing state");
    assert_eq!(
        active.page().items()[0].hydration_state(),
        HydrationState::Refreshing
    );

    write(
        &database.executor,
        "UPDATE job_run SET state = 'completed', completed_at = 3
        WHERE job_run_id = '17171717171717171717171717171717';",
    );
    assert_eq!(revision(&database.executor), initial_revision + 3);
    let completed = fenced_list(&database.executor, list_query(None, 10, None), None)
        .expect("completed root refresh removes refreshing state");
    assert_eq!(
        completed.page().items()[0].hydration_state(),
        HydrationState::PartiallyHydrated
    );
    database.executor.shutdown().expect("close database");
}

#[test]
fn revision_fenced_pages_authenticate_query_shape_and_reject_stale_views() {
    let database = open();
    insert_two_games(&database.executor);
    let first_query = list_query(None, 1, None);
    let first = fenced_list(&database.executor, first_query, None).expect("first fenced page");
    assert_eq!(first.page().items().len(), 1);
    let next_cursor = first
        .page()
        .next_cursor()
        .cloned()
        .expect("second page exists");
    let token = first.view_token().clone();
    let missing_game =
        argus_domain::GameId::try_from("cccccccccccccccccccccccccccccccc").expect("game identity");
    assert_eq!(
        fenced_game(&database.executor, missing_game, token.clone()).expect("fenced detail"),
        GetGameResult::NotFound
    );

    let second = fenced_list(
        &database.executor,
        list_query(Some(next_cursor.clone()), 1, None),
        Some(token.clone()),
    )
    .expect("continuation page uses the same view");
    assert_eq!(second.page().items().len(), 1);
    assert_eq!(second.view_token(), &token);

    let search_page = fenced_list(&database.executor, list_query(None, 1, Some("alpha")), None)
        .expect("search view page");
    let search_cursor = search_page
        .page()
        .next_cursor()
        .cloned()
        .expect("search continuation exists");
    assert!(matches!(
        fenced_list(
            &database.executor,
            list_query(Some(search_cursor.clone()), 1, Some("alpha")),
            Some(token.clone())
        ),
        Err(ApplicationPortError::LibraryViewTokenInvalid)
    ));

    let mut tampered = token.as_str().to_owned();
    let final_byte = tampered.pop().expect("token has a MAC");
    tampered.push(if final_byte == 'a' { 'b' } else { 'a' });
    let tampered = LibraryViewToken::try_from_external(tampered).expect("bounded token");
    assert!(matches!(
        fenced_list(
            &database.executor,
            list_query(Some(next_cursor.clone()), 1, None),
            Some(tampered)
        ),
        Err(ApplicationPortError::LibraryViewTokenInvalid)
    ));

    write(
        &database.executor,
        "UPDATE game_library_row SET display_title = 'Changed', updated_at = '2'
         WHERE game_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';",
    );
    assert!(matches!(
        fenced_list(
            &database.executor,
            list_query(Some(next_cursor), 1, None),
            Some(token.clone())
        ),
        Err(ApplicationPortError::LibraryViewStale)
    ));
    assert!(matches!(
        fenced_game(&database.executor, missing_game, token),
        Err(ApplicationPortError::LibraryViewStale)
    ));
    database.executor.shutdown().expect("close database");
}

#[test]
fn same_process_reopen_keeps_tokens_valid_but_a_new_process_key_rejects_replay() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("library.sqlite3");
    let key = [0x6a; 32];
    let executor =
        SqliteDatabaseExecutor::open_with_capacity_and_view_key(&path, DEFAULT_QUEUE_CAPACITY, key)
            .expect("database opens");
    insert_two_games(&executor);
    let first = fenced_list(&executor, list_query(None, 1, None), None).expect("first page");
    let cursor = first
        .page()
        .next_cursor()
        .cloned()
        .expect("continuation exists");
    let token = first.view_token().clone();
    executor.shutdown().expect("close first connection");

    let reopened =
        SqliteDatabaseExecutor::open_with_capacity_and_view_key(&path, DEFAULT_QUEUE_CAPACITY, key)
            .expect("reopen with same process key");
    assert!(
        fenced_list(
            &reopened,
            list_query(Some(cursor.clone()), 1, None),
            Some(token.clone())
        )
        .is_ok()
    );
    reopened.shutdown().expect("close same-key connection");

    let restarted = SqliteDatabaseExecutor::open_with_capacity_and_view_key(
        &path,
        DEFAULT_QUEUE_CAPACITY,
        [0x7b; 32],
    )
    .expect("reopen with a new process key");
    assert!(matches!(
        fenced_list(&restarted, list_query(Some(cursor), 1, None), Some(token)),
        Err(ApplicationPortError::LibraryViewTokenInvalid)
    ));
    restarted.shutdown().expect("close new-key connection");
}

#[test]
fn query_contract_transition_and_generation_rotation_invalidate_tokens() {
    let database = open();
    insert_two_games(&database.executor);
    let first = fenced_list(&database.executor, list_query(None, 1, None), None)
        .expect("first fenced page");
    let cursor = first.page().next_cursor().cloned().expect("continuation");
    let token = first.view_token().clone();
    database
        .executor
        .execute(&context("advance_query_contract"), |mut work| {
            work.advance_library_query_contract_version()?;
            work.commit()?;
            Ok(())
        })
        .expect("advance query-contract version atomically");
    assert_eq!(query_contract_version(&database.executor), 2);
    assert!(matches!(
        fenced_list(
            &database.executor,
            list_query(Some(cursor), 1, None),
            Some(token)
        ),
        Err(ApplicationPortError::LibraryViewStale)
    ));

    write(
        &database.executor,
        "UPDATE library_view_state
         SET query_contract_version = 9223372036854775807,
             identity_membership_revision = 9
         WHERE singleton_key = 1;",
    );
    let max_version_page = fenced_list(&database.executor, list_query(None, 1, None), None)
        .expect("read at maximum query-contract version");
    let max_version_cursor = max_version_page
        .page()
        .next_cursor()
        .cloned()
        .expect("maximum-version continuation");
    let max_version_token = max_version_page.view_token().clone();
    let before_version_rotation = generation(&database.executor);
    database
        .executor
        .execute(&context("rotate_query_contract"), |mut work| {
            work.advance_library_query_contract_version()?;
            work.commit()?;
            Ok(())
        })
        .expect("rotate generation on query-contract overflow");
    assert_ne!(generation(&database.executor), before_version_rotation);
    assert_eq!(revision(&database.executor), 1);
    assert_eq!(identity_membership_revision(&database.executor), 1);
    assert_eq!(query_contract_version(&database.executor), 1);
    assert!(matches!(
        fenced_list(
            &database.executor,
            list_query(Some(max_version_cursor), 1, None),
            Some(max_version_token)
        ),
        Err(ApplicationPortError::LibraryViewStale)
    ));

    write(
        &database.executor,
        "UPDATE library_view_state
         SET membership_revision = 9223372036854775807,
             identity_membership_revision = 9223372036854775807
         WHERE singleton_key = 1;",
    );
    let max_revision_page = fenced_list(&database.executor, list_query(None, 1, None), None)
        .expect("read at maximum membership revision");
    let max_revision_cursor = max_revision_page
        .page()
        .next_cursor()
        .cloned()
        .expect("maximum-revision continuation");
    let max_revision_token = max_revision_page.view_token().clone();
    let before_revision_rotation = generation(&database.executor);
    write(
        &database.executor,
        "UPDATE game_library_row SET display_title = 'Rotation', updated_at = '3'
         WHERE game_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';",
    );
    assert_ne!(generation(&database.executor), before_revision_rotation);
    assert_eq!(revision(&database.executor), 1);
    assert_eq!(identity_membership_revision(&database.executor), 1);
    assert!(matches!(
        fenced_list(
            &database.executor,
            list_query(Some(max_revision_cursor), 1, None),
            Some(max_revision_token)
        ),
        Err(ApplicationPortError::LibraryViewStale)
    ));
    database.executor.shutdown().expect("close database");
}
