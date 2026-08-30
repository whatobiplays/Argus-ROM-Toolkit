#![cfg(feature = "test-support")]

use std::fmt::Write as _;

use argus_application::{
    ApplicationPortError, EnrichmentUnitOfWork, GetGameResult, LibraryFacetQuery, LibraryFilter,
    LibraryScope, LogicalContentUnitOfWork, LogicalLibraryQueries, MetadataRepository,
    OperationContext, OperationName, PlatformId, ResolvedMetadata, SubsystemName, TraceId,
};
use argus_infrastructure::sqlite::{SqliteDatabaseExecutor, SqliteQueryMetrics};
use tempfile::tempdir;

const GAME_COUNT: usize = 10_000;

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(1702_u128).expect("trace"),
        SubsystemName::try_from("library_scale_tests").expect("subsystem"),
        OperationName::try_from("bounded_query").expect("operation"),
    )
}

fn seed(executor: &SqliteDatabaseExecutor) {
    executor
        .with_connection_for_tests(context(), |connection| {
            let mut sql = String::with_capacity(GAME_COUNT * 300);
            for index in 1..=GAME_COUNT {
                let game_id = format!("{index:032x}");
                let (platform, platform_id) = if index % 2 == 0 {
                    ("nintendo.gb", "nintendo.gb")
                } else {
                    ("nintendo.nes", "nintendo.nes")
                };
                writeln!(
                    sql,
                    "INSERT INTO game
                        (game_id, platform_id, lifecycle_state, grouping_revision,
                         fallback_title, fallback_title_provenance, hydration_state,
                         created_at, updated_at)
                     VALUES ('{game_id}', '{platform}', 'active', 1,
                             'Game {index:05}', 'local_fallback', 'hydrated', '1', '{index}');
                     INSERT INTO game_library_row
                        (game_id, display_title, display_title_provenance, platform_id,
                         presentation_region, selected_cover_asset_id, release_date,
                         search_text, hydration_state, availability_state,
                         content_count, source_count, updated_at)
                     VALUES ('{game_id}', 'Game {index:05}', 'local_fallback', '{platform_id}',
                             'us', NULL, NULL, 'game {index:05}', 'hydrated',
                             'available', 0, 0, '{index}');"
                )
                .expect("format seed SQL");
            }
            connection.execute_batch(&sql)?;
            Ok(())
        })
        .expect("seed scale fixture");
}

fn query_metrics(executor: &SqliteDatabaseExecutor, sql: &str) -> SqliteQueryMetrics {
    let sql = sql.to_owned();
    executor
        .with_connection_for_tests(context(), move |connection| {
            connection.query_metrics_for_tests(&sql)
        })
        .expect("query metrics")
}

fn query_plan(executor: &SqliteDatabaseExecutor, sql: &str) -> Vec<String> {
    let sql = sql.to_owned();
    executor
        .with_connection_for_tests(context(), move |connection| {
            connection.explain_query_plan_for_tests(&sql)
        })
        .expect("query plan")
}

fn install_projection_write_counter(executor: &SqliteDatabaseExecutor) {
    executor
        .with_connection_for_tests(context(), |connection| {
            connection.execute_batch(
                "CREATE TEMP TABLE projection_write_counter (game_id TEXT NOT NULL);
                 CREATE TEMP TRIGGER projection_write_counter_trigger
                 AFTER UPDATE ON game_library_row
                 BEGIN
                   INSERT INTO projection_write_counter(game_id) VALUES (NEW.game_id);
                 END;",
            )?;
            Ok(())
        })
        .expect("install projection write counter");
}

fn projection_write_ids(executor: &SqliteDatabaseExecutor) -> String {
    executor
        .with_connection_for_tests(context(), |connection| {
            connection.scalar_text(
                "SELECT COALESCE(group_concat(game_id, ','), '')
                 FROM projection_write_counter",
            )
        })
        .expect("read projection write counter")
}

fn seed_detail_fixture(
    executor: &SqliteDatabaseExecutor,
    content_count: usize,
) -> argus_domain::GameId {
    let mut game_bytes = [0xee; 16];
    game_bytes[0] = u8::try_from(content_count).expect("detail fixture size");
    let game_id = argus_domain::GameId::from_bytes(game_bytes).expect("detail game id");
    let raw_game_id = game_id.to_string();
    executor
        .with_connection_for_tests(context(), move |connection| {
            let mut sql = String::new();
            writeln!(
                sql,
                "INSERT INTO game
                    (game_id, platform_id, lifecycle_state, grouping_revision,
                     fallback_title, fallback_title_provenance, hydration_state,
                     created_at, updated_at)
                 VALUES ('{raw_game_id}', 'nintendo.gb', 'active', 1,
                         'Detail fixture', 'local_fallback', 'hydrated', '1', '1');
                 INSERT INTO game_library_row
                    (game_id, display_title, display_title_provenance, platform_id,
                     hydration_state, availability_state, content_count, source_count,
                     updated_at)
                 VALUES ('{raw_game_id}', 'Detail fixture', 'local_fallback', 'nintendo.gb',
                         'hydrated', 'available', {content_count}, 0, '1');"
            )
            .expect("format detail game SQL");
            for index in 1..=content_count {
                let content_id = format!("{:032x}", content_count * 1_000 + index);
                let membership_id = format!("{:032x}", 0x10000 + content_count * 1_000 + index);
                let relationship = if index == 1 {
                    "primary_content"
                } else {
                    "equivalent_release_representation"
                };
                writeln!(
                    sql,
                    "INSERT INTO game_content
                        (game_content_id, platform_id, content_type, presence_state,
                         identification_state, grouping_revision, created_at, updated_at)
                     VALUES ('{content_id}', 'nintendo.gb', 'CartridgeImage', 'available',
                             'unidentified', 1, '1', '1');
                     INSERT INTO game_membership
                        (game_membership_id, game_id, game_content_id, relationship,
                         grouping_basis, grouping_revision, is_current, created_at, updated_at)
                     VALUES ('{membership_id}', '{raw_game_id}', '{content_id}', '{relationship}',
                             'provisional', 1, 1, '1', '1');"
                )
                .expect("format detail content SQL");
            }
            connection.execute_batch(&sql)?;
            Ok(())
        })
        .expect("seed detail fixture");
    game_id
}

fn detail_statement_count(
    executor: &SqliteDatabaseExecutor,
    game_id: argus_domain::GameId,
) -> (usize, usize) {
    let (result, statement_count) = executor
        .with_unit_of_work_and_statement_count_for_tests(context(), move |mut work| {
            let result = {
                let mut logical = work.logical_content();
                logical
                    .get_game(game_id)
                    .map_err(ApplicationPortError::from)?
            };
            work.commit()?;
            Ok(result)
        })
        .expect("detail query");
    let content_count = match result {
        GetGameResult::Found(detail) => detail.content().len(),
        other => panic!("expected detail result, got {other:?}"),
    };
    (content_count, statement_count)
}

#[test]
fn ten_thousand_games_remain_page_bounded_and_cursor_continuable() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("library.sqlite3")).expect("open");
    seed(&executor);

    let first_query = argus_application::ListGamesQuery::builder()
        .page_size(25)
        .build()
        .expect("first query");
    let first = executor
        .with_unit_of_work(context(), move |mut work| {
            let page = {
                let mut logical = work.logical_content();
                logical
                    .list_games(&first_query)
                    .map_err(ApplicationPortError::from)?
            };
            work.commit()?;
            Ok(page)
        })
        .expect("first page");
    assert_eq!(first.items().len(), 25);
    let first_cursor = first.next_cursor().cloned().expect("continuation cursor");

    let second_query = argus_application::ListGamesQuery::builder()
        .cursor(Some(first_cursor))
        .page_size(25)
        .build()
        .expect("second query");
    let second = executor
        .with_unit_of_work(context(), move |mut work| {
            let page = {
                let mut logical = work.logical_content();
                logical
                    .list_games(&second_query)
                    .map_err(ApplicationPortError::from)?
            };
            work.commit()?;
            Ok(page)
        })
        .expect("second page");
    assert_eq!(second.items().len(), 25);
    assert_ne!(
        first.items().first().expect("first item").game_id(),
        second.items().first().expect("second item").game_id()
    );

    let filters = LibraryFilter::new(
        vec![PlatformId::NintendoGb],
        Vec::new(),
        Vec::new(),
        Vec::new(),
    )
    .expect("facet filters");
    let facet_query =
        LibraryFacetQuery::new(LibraryScope::All, Some("game 001".to_owned()), filters)
            .expect("facet query");
    let facets = executor
        .with_unit_of_work(context(), move |mut work| {
            let facets = {
                let mut logical = work.logical_content();
                logical
                    .get_library_facets(&facet_query)
                    .map_err(ApplicationPortError::from)?
            };
            work.commit()?;
            Ok(facets)
        })
        .expect("facets");
    assert_eq!(
        facets
            .platforms()
            .iter()
            .find(|bucket| bucket.platform_id() == PlatformId::NintendoGb)
            .expect("Game Boy facet")
            .count(),
        50
    );

    executor.shutdown().expect("shutdown");
}

#[test]
fn ten_thousand_game_page_and_cursor_queries_use_bounded_indexed_work() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("library.sqlite3")).expect("open");
    seed(&executor);

    let page_sql = "SELECT r.game_id
        FROM game_library_row AS r
        CROSS JOIN game AS g ON g.game_id = r.game_id
        WHERE g.lifecycle_state = 'active'
          AND NOT EXISTS (
              SELECT 1 FROM game_redirect AS redirect
              WHERE redirect.game_id = r.game_id
          )
        ORDER BY r.display_title COLLATE NOCASE ASC, r.game_id ASC
        LIMIT 26";
    let cursor_sql = "SELECT r.game_id
        FROM game_library_row AS r
        CROSS JOIN game AS g ON g.game_id = r.game_id
        WHERE g.lifecycle_state = 'active'
          AND NOT EXISTS (
              SELECT 1 FROM game_redirect AS redirect
              WHERE redirect.game_id = r.game_id
          )
          AND (r.display_title COLLATE NOCASE > 'Game 00500'
               OR (r.display_title COLLATE NOCASE = 'Game 00500'
                   AND r.game_id > '000000000000000000000000000001f4'))
        ORDER BY r.display_title COLLATE NOCASE ASC, r.game_id ASC
        LIMIT 26";

    let page_metrics = query_metrics(&executor, page_sql);
    let cursor_metrics = query_metrics(&executor, cursor_sql);
    assert_eq!(page_metrics.row_count(), 26);
    assert_eq!(cursor_metrics.row_count(), 26);
    assert!(
        page_metrics.full_scan_steps() < 1_000,
        "page metrics: {page_metrics:?}"
    );
    assert!(
        cursor_metrics.full_scan_steps() < 1_000,
        "cursor metrics: {cursor_metrics:?}"
    );
    assert!(
        page_metrics.vm_steps() < 2_000,
        "page metrics: {page_metrics:?}"
    );
    assert!(
        cursor_metrics.vm_steps() < 4_000,
        "cursor metrics: {cursor_metrics:?}"
    );

    let page_plan = query_plan(&executor, page_sql).join(" | ");
    let cursor_plan = query_plan(&executor, cursor_sql).join(" | ");
    assert!(
        page_plan.contains("idx_game_library_row_default_order"),
        "page query lost the default-order index: {page_plan}"
    );
    assert!(
        cursor_plan.contains("idx_game_library_row_default_order"),
        "cursor query lost the default-order index: {cursor_plan}"
    );
    assert!(!page_plan.contains("SCAN game_library_row"));
    assert!(!cursor_plan.contains("SCAN game_library_row"));

    install_projection_write_counter(&executor);
    let metadata = ResolvedMetadata::from_persisted(
        Some("Scale mutation".to_owned()),
        Some("scale mutation".to_owned()),
        None,
        None,
        Vec::new(),
        Vec::new(),
        Vec::new(),
        None,
        Vec::new(),
        Vec::new(),
        2,
        42,
        None,
    );
    let mutation_game_id = argus_domain::GameId::try_from("00000000000000000000000000000001")
        .expect("scale mutation game id");
    executor
        .with_unit_of_work(context(), move |mut work| {
            work.metadata()
                .save_resolved_metadata(mutation_game_id, &metadata)?;
            work.commit()
        })
        .expect("mutate one scale fixture game");
    assert_eq!(
        projection_write_ids(&executor),
        "00000000000000000000000000000001"
    );

    executor.shutdown().expect("shutdown");
}

#[test]
fn facet_and_detail_queries_have_explicit_index_and_statement_bounds() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("library.sqlite3")).expect("open");
    seed(&executor);

    let facet_sql = "SELECT r.platform_id, COUNT(*)
        FROM game_library_row AS r
        CROSS JOIN game AS g ON g.game_id = r.game_id
        WHERE g.lifecycle_state = 'active'
        GROUP BY r.platform_id";
    let facet_plan = query_plan(&executor, facet_sql).join(" | ");
    let facet_metrics = query_metrics(&executor, facet_sql);
    assert_eq!(facet_metrics.row_count(), 2);
    assert!(
        facet_plan.contains("idx_game_library_row_platform"),
        "facet query lost the platform index: {facet_plan}"
    );
    assert!(!facet_plan.contains("SCAN game_library_row"));

    let one_content_game = seed_detail_fixture(&executor, 1);
    let many_content_game = seed_detail_fixture(&executor, 12);
    let (one_content_count, one_content_statements) =
        detail_statement_count(&executor, one_content_game);
    let (many_content_count, many_content_statements) =
        detail_statement_count(&executor, many_content_game);
    assert_eq!(one_content_count, 1);
    assert_eq!(many_content_count, 12);
    assert!(
        many_content_statements <= one_content_statements + 2,
        "detail statement count grew with content members: one={one_content_statements}, many={many_content_statements}"
    );

    executor.shutdown().expect("shutdown");
}
