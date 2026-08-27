#![cfg(feature = "test-support")]

use std::fmt::Write as _;

use argus_application::{
    ApplicationPortError, LibraryFacetQuery, LibraryFilter, LibraryScope, LogicalContentUnitOfWork,
    LogicalLibraryQueries, OperationContext, OperationName, PlatformId, SubsystemName, TraceId,
};
use argus_infrastructure::sqlite::SqliteDatabaseExecutor;
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
