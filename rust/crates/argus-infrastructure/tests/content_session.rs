#![cfg(feature = "test-support")]

use std::io::{self, Read};
use std::path::Path;
use std::sync::{
    Arc,
    atomic::{AtomicBool, AtomicUsize, Ordering},
};

use argus_application::{TransformationBudget, TransformationFailure};
use argus_infrastructure::content::{
    ParsingSession, STAGING_DIRECTORY_PREFIX, STAGING_MARKER_FILE, STAGING_MARKER_VALUE,
    STAGING_ROOT_LOCK_FILE, StagingSpaceProbe, cleanup_abandoned_staging,
};
use tempfile::tempdir;

fn budget(
    max_single: u64,
    max_expanded: u64,
    max_entries: u64,
    max_depth: u32,
    max_staged: u64,
    max_work: u64,
) -> TransformationBudget {
    TransformationBudget::new(
        max_single,
        max_expanded,
        max_entries,
        max_depth,
        max_staged,
        max_work,
    )
}

#[test]
fn nested_work_uses_one_cumulative_budget() {
    let staging = tempdir().expect("staging root");
    let mut session =
        ParsingSession::for_tests(budget(64, 96, 3, 2, 64, 128), staging.path(), || false);

    session.charge_expanded(48).expect("first charge");
    session.enter_container().expect("first container");
    session.charge_expanded(48).expect("nested charge");
    assert!(matches!(
        session.charge_expanded(1),
        Err(TransformationFailure::ResourceLimitExceeded)
    ));
    session.leave_container();
}

struct FailingDecodedReader;

impl Read for FailingDecodedReader {
    fn read(&mut self, _destination: &mut [u8]) -> io::Result<usize> {
        Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            "staged representation is unavailable",
        ))
    }
}

#[test]
fn decoded_staging_preserves_io_failures_as_read_failures() {
    let staging = tempdir().expect("staging root");
    let mut session =
        ParsingSession::for_tests(budget(64, 96, 3, 2, 64, 128), staging.path(), || false);
    let mut reader = FailingDecodedReader;

    assert!(matches!(
        session.stage_decoded_reader("failing", &mut reader, None),
        Err(TransformationFailure::ReadFailure)
    ));
}

#[test]
fn depth_and_derived_entry_limits_fail_closed() {
    let staging = tempdir().expect("staging root");
    let mut session =
        ParsingSession::for_tests(budget(64, 96, 3, 2, 64, 128), staging.path(), || false);

    session
        .with_container(|session| {
            session.with_container(|session| {
                assert!(matches!(
                    session.with_container(|_| Ok::<_, TransformationFailure>(())),
                    Err(TransformationFailure::ResourceLimitExceeded)
                ));
                Ok(())
            })
        })
        .expect("two nested containers");

    session.charge_derived_entry().expect("entry one");
    session.charge_derived_entry().expect("entry two");
    session.charge_derived_entry().expect("entry three");
    assert!(matches!(
        session.charge_derived_entry(),
        Err(TransformationFailure::ResourceLimitExceeded)
    ));
}

#[test]
fn staging_checks_remaining_budget_and_available_space_before_copy() {
    let staging = tempdir().expect("staging root");
    let mut session =
        ParsingSession::for_tests(budget(64, 96, 3, 2, 4, 128), staging.path(), || false);

    assert!(matches!(
        session.stage_bytes("too-large", &[1, 2, 3, 4, 5]),
        Err(TransformationFailure::ResourceLimitExceeded)
    ));
    assert_eq!(
        std::fs::read_dir(session.operation_directory())
            .expect("operation directory")
            .count(),
        1,
        "only the marker remains after a rejected stage"
    );

    let probe_calls = Arc::new(AtomicUsize::new(0));
    let low_space = Arc::new(FixedSpaceProbe {
        available: 100,
        calls: Arc::clone(&probe_calls),
    });
    let mut low_space_session = ParsingSession::for_tests_with_probe(
        budget(128, 128, 3, 2, 128, 256),
        staging.path(),
        low_space,
        || false,
    );
    assert!(matches!(
        low_space_session.stage_bytes("space-limited", &[0; 101]),
        Err(TransformationFailure::ResourceLimitExceeded)
    ));
    assert_eq!(probe_calls.load(Ordering::Relaxed), 1);
}

#[test]
fn cancellation_interrupts_copy_and_removes_partial_output() {
    let staging = tempdir().expect("staging root");
    let cancelled = Arc::new(AtomicBool::new(false));
    let cancellation_check = {
        let cancelled = Arc::clone(&cancelled);
        move || cancelled.load(Ordering::Acquire)
    };
    let mut session = ParsingSession::for_tests(
        budget(256, 256, 3, 2, 256, 256),
        staging.path(),
        cancellation_check,
    );
    let mut reader = CancellingReader {
        bytes: vec![7; 128],
        offset: 0,
        cancelled,
    };

    assert!(matches!(
        session.stage_reader("cancelled", 128, &mut reader),
        Err(TransformationFailure::Cancelled)
    ));
    assert_eq!(
        std::fs::read_dir(session.operation_directory())
            .expect("operation directory")
            .count(),
        1,
        "partial output is removed"
    );
}

#[test]
fn finishing_or_dropping_session_removes_operation_directory() {
    let staging = tempdir().expect("staging root");
    let finished_directory = {
        let session =
            ParsingSession::for_tests(budget(64, 64, 3, 2, 64, 128), staging.path(), || false);
        let directory = session.operation_directory().to_owned();
        assert!(directory.is_dir());
        session.finish().expect("finish session");
        directory
    };
    assert!(!finished_directory.exists());

    let dropped_directory = {
        let session =
            ParsingSession::for_tests(budget(64, 64, 3, 2, 64, 128), staging.path(), || false);
        session.operation_directory().to_owned()
    };
    assert!(!dropped_directory.exists());
}

#[test]
fn cleanup_removes_argus_staging_directories_after_exclusive_root_lock() {
    let staging = tempdir().expect("staging root");
    let recognized = staging
        .path()
        .join(format!("{STAGING_DIRECTORY_PREFIX}abandoned"));
    std::fs::create_dir(&recognized).expect("recognized directory");
    std::fs::write(recognized.join(STAGING_MARKER_FILE), STAGING_MARKER_VALUE).expect("marker");

    let unmarked = staging
        .path()
        .join(format!("{STAGING_DIRECTORY_PREFIX}unmarked"));
    std::fs::create_dir(&unmarked).expect("unmarked directory");

    let unrelated = staging.path().join("unrelated");
    std::fs::create_dir(&unrelated).expect("unrelated directory");
    std::fs::write(unrelated.join(STAGING_MARKER_FILE), STAGING_MARKER_VALUE)
        .expect("unrelated marker");

    let regular_file = staging
        .path()
        .join(format!("{STAGING_DIRECTORY_PREFIX}file"));
    std::fs::write(&regular_file, b"not a directory").expect("regular file");

    assert_eq!(
        cleanup_abandoned_staging(staging.path()).expect("cleanup"),
        2
    );
    assert!(!recognized.exists());
    assert!(!unmarked.exists());
    assert!(unrelated.exists());
    assert!(regular_file.exists());
    assert!(staging.path().join(STAGING_ROOT_LOCK_FILE).exists());
}

#[test]
fn cleanup_skips_operation_namespace_while_a_session_holds_shared_root_lock() {
    let staging = tempdir().expect("staging root");
    let abandoned = staging
        .path()
        .join(format!("{STAGING_DIRECTORY_PREFIX}abandoned"));
    std::fs::create_dir(&abandoned).expect("abandoned directory");

    let session =
        ParsingSession::for_tests(budget(64, 64, 3, 2, 64, 128), staging.path(), || false);
    assert_eq!(
        cleanup_abandoned_staging(staging.path()).expect("busy cleanup"),
        0
    );
    assert!(abandoned.exists());
    drop(session);

    assert_eq!(
        cleanup_abandoned_staging(staging.path()).expect("cleanup after session"),
        1
    );
    assert!(!abandoned.exists());
}

#[derive(Debug)]
struct FixedSpaceProbe {
    available: u64,
    calls: Arc<AtomicUsize>,
}

impl StagingSpaceProbe for FixedSpaceProbe {
    fn available_bytes(&self, _staging_root: &Path) -> io::Result<u64> {
        self.calls.fetch_add(1, Ordering::Relaxed);
        Ok(self.available)
    }
}

struct CancellingReader {
    bytes: Vec<u8>,
    offset: usize,
    cancelled: Arc<AtomicBool>,
}

impl Read for CancellingReader {
    fn read(&mut self, destination: &mut [u8]) -> io::Result<usize> {
        if self.offset == 0 {
            let count = destination.len().min(self.bytes.len());
            destination[..count].copy_from_slice(&self.bytes[..count]);
            self.offset = count;
            self.cancelled.store(true, Ordering::Release);
            Ok(count)
        } else {
            Ok(0)
        }
    }
}
