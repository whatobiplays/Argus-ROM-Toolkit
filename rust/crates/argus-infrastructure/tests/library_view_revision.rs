use argus_application::{
    ApplicationPortError, GameListCursor, GetGameResult, LibraryFacetQuery, LibraryFilter,
    LibraryRootAvailability, LibraryRootId, LibraryRootRepository, LibraryScope, LibrarySort,
    LibraryViewToken, ListGamesQuery, LogicalContentUnitOfWork, LogicalLibraryQueries,
    OperationContext, OperationName, RevisionFencedGameLibraryPage, SubsystemName, TraceId,
    UnitOfWork, UnitOfWorkFactory,
};
use argus_domain::HydrationState;
use argus_infrastructure::sqlite::{DEFAULT_QUEUE_CAPACITY, SqliteDatabaseExecutor};
use tempfile::tempdir;

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
        "UPDATE library_view_state SET query_contract_version = 9223372036854775807
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
        "UPDATE library_view_state SET membership_revision = 9223372036854775807
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
