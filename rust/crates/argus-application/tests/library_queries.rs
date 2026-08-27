use argus_application::{
    AvailabilityState, GameId, GameListCursor, HydrationState, LibraryFilter, LibraryRootId,
    LibraryScope, LibrarySort, LibrarySortDirection, LibrarySortField, LibrarySourceId,
    ListGamesQuery, PlatformId,
};

fn game_id(value: u8) -> GameId {
    GameId::from_bytes([value; 16]).expect("non-zero game id")
}

#[test]
fn library_query_normalizes_search_filters_and_page_size() {
    let source = LibrarySourceId::from_bytes([1; 16]).expect("source id");
    let filter = LibraryFilter::new(
        vec![
            PlatformId::NintendoGba,
            PlatformId::NintendoGba,
            PlatformId::NintendoNes,
        ],
        vec![" US ".to_owned(), "us".to_owned(), "JP".to_owned()],
        vec![HydrationState::Unmatched, HydrationState::Hydrated],
        vec![AvailabilityState::Available, AvailabilityState::Unavailable],
    )
    .expect("valid filter");

    let query = ListGamesQuery::builder()
        .scope(LibraryScope::Source(source))
        .search(Some("  zelda  ".to_owned()))
        .filters(filter)
        .sort(LibrarySort::new(
            LibrarySortField::ReleaseDate,
            LibrarySortDirection::Descending,
        ))
        .page_size(0)
        .build()
        .expect("query");

    assert_eq!(query.search(), Some("zelda"));
    assert_eq!(query.page_size(), 1);
    assert_eq!(query.scope(), LibraryScope::Source(source));
    assert_eq!(query.sort().field(), LibrarySortField::ReleaseDate);
    assert_eq!(query.sort().direction(), LibrarySortDirection::Descending);
    assert_eq!(
        query.filters().platform_ids(),
        &[PlatformId::NintendoNes, PlatformId::NintendoGba]
    );
    assert_eq!(
        query.filters().regions(),
        &["jp".to_owned(), "us".to_owned()]
    );
    assert_eq!(
        query.filters().hydration_states(),
        &[HydrationState::Hydrated, HydrationState::Unmatched]
    );
    assert_eq!(
        query.filters().availability_states(),
        &[AvailabilityState::Available, AvailabilityState::Unavailable]
    );
}

#[test]
fn library_query_supports_all_closed_scopes_and_sorts() {
    let platform = LibraryScope::Platform(PlatformId::NintendoSnes);
    let source = LibraryScope::Source(LibrarySourceId::from_bytes([2; 16]).expect("source id"));
    let root = LibraryScope::LibraryRoot(LibraryRootId::from_bytes([3; 16]).expect("root id"));

    for scope in [LibraryScope::All, platform, source, root] {
        for field in [
            LibrarySortField::DisplayTitle,
            LibrarySortField::Platform,
            LibrarySortField::ReleaseDate,
            LibrarySortField::UpdatedAt,
        ] {
            for direction in [
                LibrarySortDirection::Ascending,
                LibrarySortDirection::Descending,
            ] {
                let query = ListGamesQuery::builder()
                    .scope(scope)
                    .sort(LibrarySort::new(field, direction))
                    .build()
                    .expect("closed query shape");
                assert_eq!(query.scope(), scope);
                assert_eq!(query.sort().field(), field);
                assert_eq!(query.sort().direction(), direction);
            }
        }
    }
}

#[test]
fn cursor_is_bound_to_the_normalized_query_shape() {
    let game = game_id(4);
    let baseline_cursor = GameListCursor::from_paging_keys("Alpha", game);

    let baseline = ListGamesQuery::builder()
        .cursor(Some(baseline_cursor.clone()))
        .build()
        .expect("legacy baseline cursor remains valid");
    assert!(baseline.cursor().is_some());

    let search = ListGamesQuery::builder()
        .search(Some("alpha".to_owned()))
        .cursor(Some(baseline_cursor))
        .build();
    assert!(
        search.is_err(),
        "a baseline cursor cannot cross query shapes"
    );

    let query = ListGamesQuery::builder()
        .search(Some("alpha".to_owned()))
        .build()
        .expect("search query");
    let bound_cursor = GameListCursor::from_query_position(
        &query,
        "Alpha",
        PlatformId::NintendoNes,
        None,
        100,
        game,
    );
    let continued = ListGamesQuery::builder()
        .search(Some(" alpha ".to_owned()))
        .cursor(Some(bound_cursor))
        .build()
        .expect("same normalized query shape");
    assert_eq!(
        continued.cursor().expect("cursor").as_str(),
        query_cursor(&continued)
    );
}

fn query_cursor(query: &ListGamesQuery) -> &str {
    query.cursor().expect("cursor").as_str()
}

#[test]
fn malformed_regions_and_page_sizes_are_rejected_or_bounded() {
    assert!(LibraryFilter::new(Vec::new(), vec!["".to_owned()], Vec::new(), Vec::new()).is_err());
    assert!(LibraryFilter::new(Vec::new(), vec!["\n".to_owned()], Vec::new(), Vec::new()).is_err());

    let query = ListGamesQuery::builder()
        .page_size(10_000)
        .build()
        .expect("page size clamps");
    assert_eq!(query.page_size(), 500);
}
