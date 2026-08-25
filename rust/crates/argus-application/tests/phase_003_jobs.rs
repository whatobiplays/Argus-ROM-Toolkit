use argus_application::{
    GameId, JobRunId, LibraryRefreshJobDetail, LibraryRefreshTrigger,
    LibraryResolutionRefreshJobDetail, OPERATION_TYPE_GAME_REFRESH, OPERATION_TYPE_LIBRARY_REFRESH,
    OPERATION_TYPE_LIBRARY_RESOLUTION_REFRESH, RefreshMode, RefreshProgressFacts,
};

fn job_run_id() -> JobRunId {
    JobRunId::from_bytes([1; 16]).expect("non-zero job identity")
}

fn game_id() -> GameId {
    GameId::from_bytes([2; 16]).expect("non-zero game identity")
}

#[test]
fn phase_003_operation_types_are_stable_and_distinct() {
    assert_eq!(OPERATION_TYPE_LIBRARY_REFRESH, "library_refresh");
    assert_eq!(OPERATION_TYPE_GAME_REFRESH, "game_refresh");
    assert_eq!(
        OPERATION_TYPE_LIBRARY_RESOLUTION_REFRESH,
        "library_resolution_refresh"
    );
    assert_ne!(
        OPERATION_TYPE_LIBRARY_REFRESH,
        OPERATION_TYPE_LIBRARY_RESOLUTION_REFRESH
    );
}

#[test]
fn refresh_details_preserve_typed_intent_and_bounded_progress() {
    let progress = RefreshProgressFacts::new(
        Some("hydrating".to_owned()),
        Some(2),
        Some(3),
        Some("library_refresh.hydrating".to_owned()),
        Some(1),
    )
    .expect("bounded progress");
    let detail = LibraryRefreshJobDetail::new(
        LibraryRefreshTrigger::AddedRoot(
            argus_application::LibraryRootId::from_bytes([3; 16]).expect("non-zero root identity"),
        ),
        RefreshMode::EligibleOnly,
        vec![
            argus_application::LibraryRootId::from_bytes([3; 16]).expect("non-zero root identity"),
        ],
        progress.clone(),
        None,
        None,
    );

    assert_eq!(
        detail.trigger(),
        LibraryRefreshTrigger::AddedRoot(
            argus_application::LibraryRootId::from_bytes([3; 16]).expect("non-zero root identity")
        )
    );
    assert_eq!(detail.mode(), RefreshMode::EligibleOnly);
    assert_eq!(detail.progress(), &progress);
    assert_eq!(detail.requested_root_ids().len(), 1);

    let resolution = LibraryResolutionRefreshJobDetail::new(job_run_id(), 7, progress, None, None);
    assert_eq!(resolution.settings_revision(), 7);
    assert_eq!(resolution.progress().completed_units(), Some(2));
    assert_eq!(game_id().as_bytes(), [2; 16]);
}
