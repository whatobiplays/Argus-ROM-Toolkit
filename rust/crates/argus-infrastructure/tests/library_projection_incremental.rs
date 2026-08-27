#![cfg(feature = "test-support")]

use argus_application::{
    EnrichmentUnitOfWork, MetadataRepository, OperationContext, OperationName, ResolvedMetadata,
    SubsystemName, TraceId,
};
use argus_domain::GameId;
use argus_infrastructure::sqlite::SqliteDatabaseExecutor;
use tempfile::tempdir;

const GAME_ONE: &str = "11111111111111111111111111111111";
const GAME_TWO: &str = "22222222222222222222222222222222";

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(1701_u128).expect("trace"),
        SubsystemName::try_from("library_projection_tests").expect("subsystem"),
        OperationName::try_from("incremental_projection").expect("operation"),
    )
}

fn seed(executor: &SqliteDatabaseExecutor) {
    executor
        .with_connection_for_tests(context(), |connection| {
            connection.execute_batch(&format!(
                "
                INSERT INTO game
                    (game_id, platform_id, lifecycle_state, grouping_revision,
                     fallback_title, fallback_title_provenance, hydration_state,
                     created_at, updated_at)
                VALUES
                    ('{GAME_ONE}', 'nintendo.gb', 'active', 1, 'Fallback One',
                     'local_fallback', 'hydrated', '1', '1'),
                    ('{GAME_TWO}', 'nintendo.nes', 'active', 1, 'Fallback Two',
                     'local_fallback', 'hydrated', '1', '1');
                INSERT INTO game_library_row
                    (game_id, display_title, display_title_provenance, platform_id,
                     presentation_region, selected_cover_asset_id, release_date,
                     search_text, hydration_state, availability_state,
                     content_count, source_count, updated_at)
                VALUES
                    ('{GAME_ONE}', 'Fallback One', 'local_fallback', 'nintendo.gb',
                     NULL, NULL, NULL, 'fallback one', 'hydrated',
                     'inactive_orphan', 0, 0, '1'),
                    ('{GAME_TWO}', 'Fallback Two', 'local_fallback', 'nintendo.nes',
                     NULL, NULL, NULL, 'fallback two', 'hydrated',
                     'inactive_orphan', 0, 0, '1');
                "
            ))?;
            Ok(())
        })
        .expect("seed projection rows");
}

fn row(
    executor: &SqliteDatabaseExecutor,
    game_id: &str,
) -> (String, String, Option<String>, Option<String>, String) {
    let game_id = game_id.to_owned();
    executor
        .with_connection_for_tests(context(), move |connection| {
            let encoded = connection.scalar_text(&format!(
                "SELECT display_title || char(31) || display_title_provenance || char(31) ||
                        COALESCE(presentation_region, '') || char(31) ||
                        COALESCE(release_date, '') || char(31) || search_text
                 FROM game_library_row
                 WHERE game_id = '{game_id}'"
            ))?;
            let mut fields = encoded.split('\u{1f}');
            let title = fields.next().expect("title field").to_owned();
            let provenance = fields.next().expect("provenance field").to_owned();
            let region = match fields.next().expect("region field") {
                "" => None,
                value => Some(value.to_owned()),
            };
            let release_date = match fields.next().expect("release date field") {
                "" => None,
                value => Some(value.to_owned()),
            };
            let search_text = fields.next().expect("search field").to_owned();
            Ok((title, provenance, region, release_date, search_text))
        })
        .expect("read projection row")
}

#[test]
fn resolved_metadata_refreshes_only_the_affected_game_projection() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("library.sqlite3")).expect("open");
    seed(&executor);
    let untouched_before = row(&executor, GAME_TWO);

    let metadata = ResolvedMetadata::from_persisted(
        Some("Resolved One".to_owned()),
        Some("resolved one".to_owned()),
        Some("Description".to_owned()),
        Some("1991-04-21".to_owned()),
        vec!["Developer".to_owned()],
        vec!["Publisher".to_owned()],
        vec!["Action".to_owned()],
        Some("us".to_owned()),
        vec!["en".to_owned()],
        Vec::new(),
        2,
        42,
        None,
    );
    executor
        .with_unit_of_work(context(), move |mut work| {
            work.metadata()
                .save_resolved_metadata(GameId::try_from(GAME_ONE).expect("game id"), &metadata)?;
            work.commit()
        })
        .expect("save resolved metadata");

    assert_eq!(
        row(&executor, GAME_ONE),
        (
            "Resolved One".to_owned(),
            "resolved_metadata".to_owned(),
            Some("us".to_owned()),
            Some("1991-04-21".to_owned()),
            "resolved one resolved one fallback one".to_owned(),
        )
    );
    assert_eq!(row(&executor, GAME_TWO), untouched_before);
    executor.shutdown().expect("shutdown");
}
