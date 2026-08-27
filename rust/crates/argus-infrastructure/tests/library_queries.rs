#![cfg(feature = "test-support")]

use argus_application::{
    ApplicationPortError, AvailabilityState, EnrichmentUnitOfWork, GameLibraryPage, HydrationState,
    LibraryFacetQuery, LibraryFilter, LibraryScope, LibrarySort, LibrarySortDirection,
    LibrarySortField, LogicalContentUnitOfWork, LogicalLibraryQueries, MetadataRepository,
    OperationContext, OperationName, PlatformId, ResolvedMetadata, SubsystemName, TraceId,
};
use argus_domain::GameId;
use argus_infrastructure::sqlite::SqliteDatabaseExecutor;
use tempfile::tempdir;

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(1501_u128).expect("trace"),
        SubsystemName::try_from("library_tests").expect("subsystem"),
        OperationName::try_from("queries").expect("operation"),
    )
}

fn seed(executor: &SqliteDatabaseExecutor) {
    executor
        .with_connection_for_tests(context(), |connection| {
            connection.execute_batch(
                "
                INSERT INTO library_source
                    (library_source_id, source_provider_type, display_name, provider_config,
                     config_revision, created_at, updated_at)
                VALUES
                    ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'local_filesystem', 'Source A', '{}', 1, 1, 1);
                INSERT INTO library_root
                    (library_root_id, library_source_id, root_locator, display_name,
                     safe_location_presentation, availability_status, config_revision,
                     created_at, updated_at)
                VALUES
                    ('cccccccccccccccccccccccccccccccc', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', '/a', 'Root A', '/a', 'available', 1, 1, 1),
                    ('dddddddddddddddddddddddddddddddd', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', '/b', 'Root B', '/b', 'available', 1, 1, 1);
                INSERT INTO job_run (job_run_id, operation_type, state, created_at)
                VALUES
                    ('eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee', 'library_scan', 'completed', 1),
                    ('ffffffffffffffffffffffffffffffff', 'library_scan', 'completed', 1);
                INSERT INTO scan_run
                    (scan_run_id, job_run_id, historical_library_root_id, root_locator,
                     root_display_name, safe_location_display, source_config_revision,
                     root_config_revision, status, started_at)
                VALUES
                    ('12121212121212121212121212121212', 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee', 'cccccccccccccccccccccccccccccccc', '/a', 'Root A', '/a', 1, 1, 'complete', 1),
                    ('13131313131313131313131313131313', 'ffffffffffffffffffffffffffffffff', 'dddddddddddddddddddddddddddddddd', '/b', 'Root B', '/b', 1, 1, 'complete', 1);
                INSERT INTO source_entry
                    (source_entry_id, library_root_id, coordinate_kind, relative_locator,
                     locator_key, display_name, display_location, kind, classification,
                     source_fingerprint, last_observed_scan_id, created_at, updated_at)
                VALUES
                    ('14141414141414141414141414141414', 'cccccccccccccccccccccccccccccccc', 'provider', 'alpha.gb', 'alpha.gb', 'alpha.gb', 'alpha.gb', 'file', 'content_candidate', 'alpha-v1', '12121212121212121212121212121212', 1, 1),
                    ('15151515151515151515151515151515', 'dddddddddddddddddddddddddddddddd', 'provider', 'alpha-copy.gb', 'alpha-copy.gb', 'alpha-copy.gb', 'alpha-copy.gb', 'file', 'content_candidate', 'alpha-copy-v1', '13131313131313131313131313131313', 1, 1),
                    ('16161616161616161616161616161616', 'cccccccccccccccccccccccccccccccc', 'provider', 'beta.nes', 'beta.nes', 'beta.nes', 'beta.nes', 'file', 'content_candidate', 'beta-v1', '12121212121212121212121212121212', 1, 1),
                    ('17171717171717171717171717171717', 'dddddddddddddddddddddddddddddddd', 'provider', 'gamma.sms', 'gamma.sms', 'gamma.sms', 'gamma.sms', 'file', 'content_candidate', 'gamma-v1', '13131313131313131313131313131313', 1, 1);
                INSERT INTO game_content
                    (game_content_id, platform_id, content_type, presence_state,
                     identification_state, grouping_revision, created_at, updated_at)
                VALUES
                    ('21212121212121212121212121212121', 'nintendo.gb', 'CartridgeImage', 'available', 'identified', 1, 1, 1),
                    ('22222222222222222222222222222222', 'nintendo.nes', 'CartridgeImage', 'partially_unavailable', 'identified', 1, 1, 1),
                    ('23232323232323232323232323232323', 'nintendo.gb', 'CartridgeImage', 'unavailable', 'identified', 1, 1, 1),
                    ('24242424242424242424242424242424', 'sega.sms', 'CartridgeImage', 'available', 'identified', 1, 1, 1);
                INSERT INTO game
                    (game_id, platform_id, lifecycle_state, grouping_revision, fallback_title,
                     fallback_title_provenance, hydration_state, created_at, updated_at)
                VALUES
                    ('31313131313131313131313131313131', 'nintendo.gb', 'active', 1, 'Alpha', 'local_fallback', 'hydrated', 1, 1),
                    ('32323232323232323232323232323232', 'nintendo.nes', 'active', 1, 'Beta', 'local_fallback', 'partially_hydrated', 1, 1),
                    ('33333333333333333333333333333333', 'nintendo.gb', 'active', 1, 'Beta', 'local_fallback', 'unmatched', 1, 1),
                    ('34343434343434343434343434343434', 'sega.sms', 'active', 1, 'Gamma', 'local_fallback', 'refreshing', 1, 1),
                    ('35353535353535353535353535353535', 'nintendo.gb', 'inactive_orphan', 1, 'Orphan', 'local_fallback', 'unmatched', 1, 1),
                    ('36363636363636363636363636363636', 'nintendo.gb', 'redirected', 1, 'Redirected', 'local_fallback', 'unmatched', 1, 1);
                INSERT INTO game_membership
                    (game_membership_id, game_id, game_content_id, relationship,
                     grouping_basis, grouping_revision, is_current, created_at, updated_at)
                VALUES
                    ('41414141414141414141414141414141', '31313131313131313131313131313131', '21212121212121212121212121212121', 'primary_content', 'exact_content_identity', 1, 1, 1, 1),
                    ('42424242424242424242424242424242', '32323232323232323232323232323232', '22222222222222222222222222222222', 'primary_content', 'exact_content_identity', 1, 1, 1, 1),
                    ('43434343434343434343434343434343', '33333333333333333333333333333333', '23232323232323232323232323232323', 'primary_content', 'exact_content_identity', 1, 1, 1, 1),
                    ('44444444444444444444444444444444', '34343434343434343434343434343434', '24242424242424242424242424242424', 'primary_content', 'exact_content_identity', 1, 1, 1, 1);
                INSERT INTO game_content_source
                    (game_content_source_id, game_content_id, source_entry_id, association_key,
                     source_fingerprint, last_observed_scan_id, is_current, created_at, updated_at)
                VALUES
                    ('51515151515151515151515151515151', '21212121212121212121212121212121', '14141414141414141414141414141414', 'raw', 'alpha-v1', '12121212121212121212121212121212', 1, 1, 1),
                    ('52525252525252525252525252525252', '21212121212121212121212121212121', '15151515151515151515151515151515', 'raw-copy', 'alpha-copy-v1', '13131313131313131313131313131313', 1, 1, 1),
                    ('53535353535353535353535353535353', '22222222222222222222222222222222', '16161616161616161616161616161616', 'raw', 'beta-v1', '12121212121212121212121212121212', 1, 1, 1),
                    ('54545454545454545454545454545454', '24242424242424242424242424242424', '17171717171717171717171717171717', 'raw', 'gamma-v1', '13131313131313131313131313131313', 1, 1, 1);
                INSERT INTO game_library_row
                    (game_id, display_title, display_title_provenance, platform_id,
                     presentation_region, release_date, search_text, hydration_state,
                     availability_state, content_count, source_count, updated_at)
                VALUES
                    ('31313131313131313131313131313131', 'Alpha', 'local_fallback', 'nintendo.gb', 'us', '2020-01-01', 'alpha', 'hydrated', 'available', 1, 2, '1000'),
                    ('32323232323232323232323232323232', 'Beta', 'resolved_metadata', 'nintendo.nes', 'us', '2019-01-01', 'beta beta alternate', 'partially_hydrated', 'partially_unavailable', 1, 1, '2000'),
                    ('33333333333333333333333333333333', 'Beta', 'local_fallback', 'nintendo.gb', 'jp', NULL, 'beta', 'unmatched', 'unavailable', 1, 1, '3000'),
                    ('34343434343434343434343434343434', 'Gamma', 'local_fallback', 'sega.sms', NULL, '2021-01-01', 'gamma', 'refreshing', 'available', 1, 1, '4000'),
                    ('35353535353535353535353535353535', 'Orphan', 'local_fallback', 'nintendo.gb', NULL, NULL, 'orphan', 'unmatched', 'inactive_orphan', 1, 0, '5000'),
                    ('36363636363636363636363636363636', 'Redirected', 'local_fallback', 'nintendo.gb', NULL, NULL, 'redirected', 'unmatched', 'available', 0, 0, '6000');
                INSERT INTO game_redirect (game_id, canonical_game_id, created_at)
                VALUES ('36363636363636363636363636363636', '31313131313131313131313131313131', 1);
                ",
            )?;
            Ok(())
        })
        .expect("seed library query fixtures");
}

fn list(
    executor: &SqliteDatabaseExecutor,
    query: argus_application::ListGamesQuery,
) -> GameLibraryPage {
    executor
        .with_unit_of_work(context(), move |mut work| {
            let page = {
                let mut logical = work.logical_content();
                logical
                    .list_games(&query)
                    .map_err(ApplicationPortError::from)?
            };
            work.commit()?;
            Ok(page)
        })
        .expect("list games")
}

fn game_ids(page: &GameLibraryPage) -> Vec<String> {
    page.items()
        .iter()
        .map(|row| row.game_id().to_string())
        .collect()
}

#[test]
fn scoped_search_filter_sort_and_cursor_queries_are_backend_owned() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("library.sqlite3")).expect("database");
    seed(&executor);

    let first_query = argus_application::ListGamesQuery::builder()
        .page_size(2)
        .build()
        .expect("default query");
    let first = list(&executor, first_query.clone());
    assert_eq!(
        game_ids(&first),
        vec![
            "31313131313131313131313131313131",
            "32323232323232323232323232323232",
        ]
    );
    let second_query = argus_application::ListGamesQuery::builder()
        .cursor(first.next_cursor().cloned())
        .page_size(2)
        .build()
        .expect("continuation query");
    assert_eq!(
        game_ids(&list(&executor, second_query)),
        vec![
            "33333333333333333333333333333333",
            "34343434343434343434343434343434",
        ]
    );

    let scoped = argus_application::ListGamesQuery::builder()
        .scope(LibraryScope::LibraryRoot(
            argus_application::LibraryRootId::try_from("dddddddddddddddddddddddddddddddd")
                .expect("root"),
        ))
        .build()
        .expect("root query");
    assert_eq!(
        game_ids(&list(&executor, scoped)),
        vec![
            "31313131313131313131313131313131",
            "34343434343434343434343434343434",
        ]
    );

    let filters = LibraryFilter::new(
        vec![PlatformId::NintendoGb, PlatformId::NintendoNes],
        vec![" US ".to_owned()],
        vec![HydrationState::Hydrated, HydrationState::PartiallyHydrated],
        vec![
            AvailabilityState::Available,
            AvailabilityState::PartiallyUnavailable,
        ],
    )
    .expect("filters");
    let filtered = argus_application::ListGamesQuery::builder()
        .filters(filters)
        .search(Some("  ALTERNATE  ".to_owned()))
        .build()
        .expect("filtered query");
    assert_eq!(
        game_ids(&list(&executor, filtered)),
        vec!["32323232323232323232323232323232",]
    );

    for (field, direction, expected) in [
        (
            LibrarySortField::DisplayTitle,
            LibrarySortDirection::Ascending,
            vec![
                "31313131313131313131313131313131",
                "32323232323232323232323232323232",
                "33333333333333333333333333333333",
                "34343434343434343434343434343434",
            ],
        ),
        (
            LibrarySortField::DisplayTitle,
            LibrarySortDirection::Descending,
            vec![
                "34343434343434343434343434343434",
                "33333333333333333333333333333333",
                "32323232323232323232323232323232",
                "31313131313131313131313131313131",
            ],
        ),
        (
            LibrarySortField::Platform,
            LibrarySortDirection::Ascending,
            vec![
                "31313131313131313131313131313131",
                "33333333333333333333333333333333",
                "32323232323232323232323232323232",
                "34343434343434343434343434343434",
            ],
        ),
        (
            LibrarySortField::Platform,
            LibrarySortDirection::Descending,
            vec![
                "34343434343434343434343434343434",
                "32323232323232323232323232323232",
                "33333333333333333333333333333333",
                "31313131313131313131313131313131",
            ],
        ),
        (
            LibrarySortField::ReleaseDate,
            LibrarySortDirection::Ascending,
            vec![
                "32323232323232323232323232323232",
                "31313131313131313131313131313131",
                "34343434343434343434343434343434",
                "33333333333333333333333333333333",
            ],
        ),
        (
            LibrarySortField::ReleaseDate,
            LibrarySortDirection::Descending,
            vec![
                "34343434343434343434343434343434",
                "31313131313131313131313131313131",
                "32323232323232323232323232323232",
                "33333333333333333333333333333333",
            ],
        ),
        (
            LibrarySortField::UpdatedAt,
            LibrarySortDirection::Ascending,
            vec![
                "31313131313131313131313131313131",
                "32323232323232323232323232323232",
                "33333333333333333333333333333333",
                "34343434343434343434343434343434",
            ],
        ),
        (
            LibrarySortField::UpdatedAt,
            LibrarySortDirection::Descending,
            vec![
                "34343434343434343434343434343434",
                "33333333333333333333333333333333",
                "32323232323232323232323232323232",
                "31313131313131313131313131313131",
            ],
        ),
    ] {
        let query = argus_application::ListGamesQuery::builder()
            .sort(LibrarySort::new(field, direction))
            .page_size(10)
            .build()
            .expect("date query");
        assert_eq!(game_ids(&list(&executor, query)), expected);
    }

    executor.shutdown().expect("shutdown");
}

#[test]
fn facets_exclude_their_own_category_and_ignore_paging_sort() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("facets.sqlite3")).expect("database");
    seed(&executor);
    let filters = LibraryFilter::new(
        vec![PlatformId::NintendoGb],
        Vec::new(),
        Vec::new(),
        Vec::new(),
    )
    .expect("filters");
    let query = LibraryFacetQuery::new(LibraryScope::All, Some("beta".to_owned()), filters)
        .expect("facet query");
    let facets = executor
        .with_unit_of_work(context(), move |mut work| {
            let value = {
                let mut logical = work.logical_content();
                logical
                    .get_library_facets(&query)
                    .map_err(ApplicationPortError::from)?
            };
            work.commit()?;
            Ok(value)
        })
        .expect("facets");

    assert_eq!(
        facets
            .platforms()
            .iter()
            .map(|bucket| (bucket.platform_id(), bucket.count()))
            .collect::<Vec<_>>(),
        vec![(PlatformId::NintendoNes, 1), (PlatformId::NintendoGb, 1)]
    );
    assert_eq!(
        facets
            .regions()
            .iter()
            .map(|bucket| (bucket.region(), bucket.count()))
            .collect::<Vec<_>>(),
        vec![("jp", 1)]
    );
    assert!(
        facets
            .hydration_states()
            .iter()
            .any(|bucket| bucket.hydration_state() == HydrationState::Unmatched)
    );
    executor.shutdown().expect("shutdown");
}

#[test]
fn normal_queries_suppress_redirected_and_inactive_orphan_games() {
    let directory = tempdir().expect("tempdir");
    let executor = SqliteDatabaseExecutor::open(directory.path().join("eligibility.sqlite3"))
        .expect("database");
    seed(&executor);
    let query = argus_application::ListGamesQuery::builder()
        .sort(LibrarySort::new(
            LibrarySortField::UpdatedAt,
            LibrarySortDirection::Descending,
        ))
        .build()
        .expect("query");
    let ids = game_ids(&list(&executor, query));
    assert_eq!(ids.len(), 4);
    assert!(!ids.contains(&"35353535353535353535353535353535".to_owned()));
    assert!(!ids.contains(&"36363636363636363636363636363636".to_owned()));
    executor.shutdown().expect("shutdown");
}

#[test]
fn oversized_projection_sort_keys_are_bounded_before_paging() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("bounded-projection.sqlite3"))
            .expect("database");
    seed(&executor);
    let game_id = GameId::try_from("32323232323232323232323232323232").expect("game id");
    let metadata = ResolvedMetadata::from_persisted(
        Some(format!("Beta {}", "😀".repeat(300))),
        Some("beta long".to_owned()),
        Some("description".to_owned()),
        Some(format!("2020-01-01{}", "x".repeat(56))),
        Vec::new(),
        Vec::new(),
        Vec::new(),
        Some("us".to_owned()),
        vec!["en".to_owned()],
        Vec::new(),
        2,
        42,
        None,
    );
    executor
        .with_unit_of_work(context(), move |mut work| {
            work.metadata().save_resolved_metadata(game_id, &metadata)?;
            work.commit()
        })
        .expect("save oversized resolved metadata");

    for sort in [
        LibrarySort::new(
            LibrarySortField::DisplayTitle,
            LibrarySortDirection::Ascending,
        ),
        LibrarySort::new(
            LibrarySortField::ReleaseDate,
            LibrarySortDirection::Ascending,
        ),
    ] {
        let mut cursor = None;
        let mut seen = Vec::new();
        for _ in 0..4 {
            let query = argus_application::ListGamesQuery::builder()
                .sort(sort)
                .cursor(cursor)
                .page_size(1)
                .build()
                .expect("paged query");
            let page = list(&executor, query);
            let row = page.items().first().expect("expected active game");
            if row.game_id() == game_id {
                assert!(row.display_title().len() <= 1024);
                assert!(row.release_date().is_none_or(|date| date.len() <= 64));
            }
            seen.push(row.game_id());
            cursor = page.next_cursor().cloned();
        }
        assert_eq!(seen.len(), 4);
        assert!(cursor.is_none());
    }

    executor.shutdown().expect("shutdown");
}
