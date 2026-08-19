#![cfg(feature = "test-support")]

//! Deterministic Slice 002 background-manager regression tests.

use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::mpsc::{self, Receiver, Sender};
use std::time::{Duration, Instant};

use argus_application::{
    ApplicationError, BackgroundOperationHandler, BackgroundOperationStopReason,
    JobProgressReporter, JobRunId, JobRunRepository, JobRunState, JobsQueries, NewJobRun,
    OperationCompletion, OperationContext, OperationHandle, OperationName, SubsystemName, TraceId,
    UnitOfWork, UnitOfWorkFactory,
};
use argus_infrastructure::sqlite::{SqliteDatabaseExecutor, SqliteJobsQueries};
use argus_runtime::EventBus;
use argus_runtime::background::{BackgroundManagerConfig, BackgroundOperationManager};
use argus_runtime::operations::ResourceClass;

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(1).expect("trace"),
        SubsystemName::try_from("test").expect("subsystem"),
        OperationName::try_from("background_manager").expect("operation"),
    )
}

fn open_executor(directory: &std::path::Path) -> SqliteDatabaseExecutor {
    SqliteDatabaseExecutor::open(directory.join("argus.sqlite3")).expect("executor")
}

fn manager(
    executor: &SqliteDatabaseExecutor,
) -> BackgroundOperationManager<SqliteDatabaseExecutor> {
    BackgroundOperationManager::new(
        executor.clone(),
        Arc::new(EventBus::new(
            Vec::new(),
            Vec::new(),
            Vec::new(),
            Vec::new(),
        )),
        BackgroundManagerConfig::default(),
    )
}

fn manager_with_deadline(
    executor: &SqliteDatabaseExecutor,
    drain_deadline: Duration,
) -> BackgroundOperationManager<SqliteDatabaseExecutor> {
    let config = BackgroundManagerConfig {
        drain_deadline,
        ..BackgroundManagerConfig::default()
    };
    BackgroundOperationManager::new(
        executor.clone(),
        Arc::new(EventBus::new(
            Vec::new(),
            Vec::new(),
            Vec::new(),
            Vec::new(),
        )),
        config,
    )
}

fn insert_job(executor: &SqliteDatabaseExecutor) -> JobRunId {
    executor
        .execute(&context(), |mut scope| {
            let id = scope.job_runs().insert(NewJobRun::new("library_scan", 1))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(id)
        })
        .expect("insert job")
}

fn job_state(executor: &SqliteDatabaseExecutor, job_run_id: JobRunId) -> JobRunState {
    SqliteJobsQueries::new(executor.clone())
        .get_job(&context(), job_run_id)
        .expect("job state read")
        .map(|detail| detail.job().state())
        .expect("job row exists")
}

fn wait_until<F>(mut predicate: F, timeout: Duration) -> bool
where
    F: FnMut() -> bool,
{
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        if predicate() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    predicate()
}

fn handle(job_run_id: JobRunId) -> OperationHandle {
    OperationHandle::new(job_run_id, "test")
}

const RESOURCES: &[ResourceClass] = &[
    ResourceClass::FilesystemRead,
    ResourceClass::PersistenceWrite,
];

/// Handler that signals when execution starts and blocks until released.
struct BlockingHandler {
    invoked: Arc<AtomicUsize>,
    started: Sender<()>,
    release: std::sync::Mutex<Receiver<()>>,
    completion: JobRunState,
}

impl BlockingHandler {
    fn new(completion: JobRunState) -> (Self, Receiver<()>, Sender<()>) {
        let (started_tx, started_rx) = mpsc::channel();
        let (release_tx, release_rx) = mpsc::channel();
        (
            Self {
                invoked: Arc::new(AtomicUsize::new(0)),
                started: started_tx,
                release: std::sync::Mutex::new(release_rx),
                completion,
            },
            started_rx,
            release_tx,
        )
    }
}

impl BackgroundOperationHandler for BlockingHandler {
    fn execute(
        &self,
        _context: &OperationContext,
        _stop_reason: &dyn Fn() -> Option<BackgroundOperationStopReason>,
        _progress: &dyn JobProgressReporter,
    ) -> Result<OperationCompletion, ApplicationError> {
        self.invoked.fetch_add(1, Ordering::SeqCst);
        let _ = self.started.send(());
        let _ = self.release.lock().expect("release lock").recv();
        Ok(OperationCompletion::new(self.completion, None, None))
    }
}

/// Handler that records invocation and optional pre-execution cleanup.
struct CountingHandler {
    invoked: Arc<AtomicUsize>,
    cleanup: Arc<AtomicUsize>,
}

impl CountingHandler {
    fn new() -> (Self, Arc<AtomicUsize>, Arc<AtomicUsize>) {
        let invoked = Arc::new(AtomicUsize::new(0));
        let cleanup = Arc::new(AtomicUsize::new(0));
        (
            Self {
                invoked: Arc::clone(&invoked),
                cleanup: Arc::clone(&cleanup),
            },
            invoked,
            cleanup,
        )
    }
}

impl BackgroundOperationHandler for CountingHandler {
    fn execute(
        &self,
        _context: &OperationContext,
        _stop_reason: &dyn Fn() -> Option<BackgroundOperationStopReason>,
        _progress: &dyn JobProgressReporter,
    ) -> Result<OperationCompletion, ApplicationError> {
        self.invoked.fetch_add(1, Ordering::SeqCst);
        Ok(OperationCompletion::new(JobRunState::Completed, None, None))
    }

    fn stopped_before_execution(
        &self,
        _context: &OperationContext,
        _reason: BackgroundOperationStopReason,
    ) -> Result<(), ApplicationError> {
        self.cleanup.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }
}

#[test]
fn queued_cancellation_never_executes_the_handler() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor = open_executor(directory.path());
    let manager = manager(&executor);
    let a_id = insert_job(&executor);
    let (a_handler, a_started, a_release) = BlockingHandler::new(JobRunState::Completed);
    let a_invoked = Arc::clone(&a_handler.invoked);
    manager
        .register(&handle(a_id), Arc::new(a_handler), RESOURCES)
        .expect("register A");
    a_started
        .recv_timeout(Duration::from_secs(5))
        .expect("A starts and holds resources");

    let b_id = insert_job(&executor);
    let (b_handler, b_invoked, b_cleanup) = CountingHandler::new();
    manager
        .register(&handle(b_id), Arc::new(b_handler), RESOURCES)
        .expect("register B");
    assert!(
        wait_until(
            || job_state(&executor, b_id) == JobRunState::Queued,
            Duration::from_secs(5)
        ),
        "B should be queued while A holds the resources"
    );
    assert_eq!(job_state(&executor, b_id), JobRunState::Queued);

    manager.notify_cancellation(b_id);
    assert!(
        wait_until(
            || job_state(&executor, b_id) == JobRunState::Cancelled,
            Duration::from_secs(5)
        ),
        "B must reach terminal Cancelled"
    );
    assert_eq!(
        b_invoked.load(Ordering::SeqCst),
        0,
        "B handler never executes"
    );
    assert_eq!(
        b_cleanup.load(Ordering::SeqCst),
        1,
        "generic cleanup seam runs"
    );

    assert_eq!(a_invoked.load(Ordering::SeqCst), 1, "A unaffected");
    assert!(
        !job_state(&executor, a_id).is_terminal(),
        "A still running while blocked"
    );

    a_release.send(()).expect("release A");
    assert!(
        wait_until(
            || job_state(&executor, a_id) == JobRunState::Completed,
            Duration::from_secs(5)
        ),
        "A completes after release"
    );

    // B's pre-execution cancellation must not leak resources.
    let c_id = insert_job(&executor);
    let (c_handler, _, _) = CountingHandler::new();
    manager
        .register(&handle(c_id), Arc::new(c_handler), RESOURCES)
        .expect("register C after cancellation");
    assert!(
        wait_until(
            || job_state(&executor, c_id) == JobRunState::Completed,
            Duration::from_secs(5)
        ),
        "C proceeds after B's queued cancellation"
    );
    manager.shutdown();
    executor.shutdown().expect("shutdown");
}

#[test]
fn shutdown_before_execution_never_executes_the_handler() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor = open_executor(directory.path());
    let manager = manager_with_deadline(&executor, Duration::from_millis(100));
    let a_id = insert_job(&executor);
    let (a_handler, a_started, a_release) = BlockingHandler::new(JobRunState::Completed);
    manager
        .register(&handle(a_id), Arc::new(a_handler), RESOURCES)
        .expect("register A");
    a_started
        .recv_timeout(Duration::from_secs(5))
        .expect("A holds resources");

    let b_id = insert_job(&executor);
    let (b_handler, b_invoked, b_cleanup) = CountingHandler::new();
    manager
        .register(&handle(b_id), Arc::new(b_handler), RESOURCES)
        .expect("register B");
    assert!(
        wait_until(
            || job_state(&executor, b_id) == JobRunState::Queued,
            Duration::from_secs(5)
        ),
        "B queued while A holds resources"
    );

    let _ = manager.shutdown();
    assert!(
        wait_until(
            || job_state(&executor, b_id) == JobRunState::Cancelled,
            Duration::from_secs(5)
        ),
        "B reaches Cancelled without executing"
    );
    assert_eq!(b_invoked.load(Ordering::SeqCst), 0);
    assert_eq!(b_cleanup.load(Ordering::SeqCst), 1);

    // A's cooperative handler may still be finishing its current work.
    a_release.send(()).expect("release A");
    assert!(
        wait_until(
            || job_state(&executor, a_id) == JobRunState::Completed,
            Duration::from_secs(5)
        ),
        "A completes after release"
    );
    executor.shutdown().expect("shutdown");
}

#[test]
fn resources_serialize_without_deadlock() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor = open_executor(directory.path());
    let manager = manager(&executor);
    let a_id = insert_job(&executor);
    let (a_handler, a_started, a_release) = BlockingHandler::new(JobRunState::Completed);
    let a_invoked = Arc::clone(&a_handler.invoked);
    manager
        .register(&handle(a_id), Arc::new(a_handler), RESOURCES)
        .expect("register A");
    a_started
        .recv_timeout(Duration::from_secs(5))
        .expect("A holds resources");

    let b_id = insert_job(&executor);
    let (b_handler, b_invoked, _) = CountingHandler::new();
    manager
        .register(&handle(b_id), Arc::new(b_handler), RESOURCES)
        .expect("register B");
    assert!(
        wait_until(
            || job_state(&executor, b_id) == JobRunState::Queued,
            Duration::from_secs(5)
        ),
        "B queued behind A"
    );
    std::thread::sleep(Duration::from_millis(50));
    assert_eq!(
        job_state(&executor, b_id),
        JobRunState::Queued,
        "B stays queued"
    );
    assert_eq!(a_invoked.load(Ordering::SeqCst), 1);
    assert_eq!(b_invoked.load(Ordering::SeqCst), 0);

    a_release.send(()).expect("release A");
    assert!(
        wait_until(
            || job_state(&executor, b_id) == JobRunState::Completed,
            Duration::from_secs(5)
        ),
        "B proceeds after A releases"
    );
    assert_eq!(b_invoked.load(Ordering::SeqCst), 1);
    assert_eq!(a_invoked.load(Ordering::SeqCst), 1);
    manager.shutdown();
    executor.shutdown().expect("shutdown");
}

#[test]
fn lifecycle_remains_queued_until_resources_are_acquired() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor = open_executor(directory.path());
    let manager = manager(&executor);
    let a_id = insert_job(&executor);
    let (a_handler, a_started, a_release) = BlockingHandler::new(JobRunState::Completed);
    manager
        .register(&handle(a_id), Arc::new(a_handler), RESOURCES)
        .expect("register A");
    a_started
        .recv_timeout(Duration::from_secs(5))
        .expect("A holds resources");

    let b_id = insert_job(&executor);
    let (b_handler, b_started, b_release) = BlockingHandler::new(JobRunState::Completed);
    manager
        .register(&handle(b_id), Arc::new(b_handler), RESOURCES)
        .expect("register B");
    assert!(
        wait_until(
            || job_state(&executor, b_id) == JobRunState::Queued,
            Duration::from_secs(5)
        ),
        "B queued while waiting"
    );
    for _ in 0..10 {
        assert_eq!(
            job_state(&executor, b_id),
            JobRunState::Queued,
            "B must remain Queued while waiting for resources"
        );
        std::thread::sleep(Duration::from_millis(10));
    }

    a_release.send(()).expect("release A");
    assert!(
        wait_until(
            || b_started.recv_timeout(Duration::from_millis(10)).is_ok(),
            Duration::from_secs(5)
        ),
        "B starts after acquisition"
    );
    assert_eq!(
        job_state(&executor, b_id),
        JobRunState::Running,
        "B runs while blocked"
    );
    b_release.send(()).expect("release B");
    assert!(
        wait_until(
            || job_state(&executor, b_id) == JobRunState::Completed,
            Duration::from_secs(5)
        ),
        "B completes"
    );
    manager.shutdown();
    executor.shutdown().expect("shutdown");
}

#[test]
fn resources_are_released_after_every_terminal_execution_path() {
    for completion in [
        JobRunState::Completed,
        JobRunState::Failed,
        JobRunState::Cancelled,
    ] {
        let directory = tempfile::tempdir().expect("tempdir");
        let executor = open_executor(directory.path());
        let manager = manager(&executor);
        let a_id = insert_job(&executor);
        let (a_handler, a_started, a_release) = BlockingHandler::new(completion);
        manager
            .register(&handle(a_id), Arc::new(a_handler), RESOURCES)
            .expect("register A");
        a_started
            .recv_timeout(Duration::from_secs(5))
            .expect("A holds resources");
        a_release.send(()).expect("release A");
        assert!(
            wait_until(
                || job_state(&executor, a_id) == completion,
                Duration::from_secs(5)
            ),
            "A terminal via {completion:?}"
        );

        let b_id = insert_job(&executor);
        let (b_handler, b_invoked, _) = CountingHandler::new();
        manager
            .register(&handle(b_id), Arc::new(b_handler), RESOURCES)
            .expect("register B");
        assert!(
            wait_until(
                || job_state(&executor, b_id) == JobRunState::Completed,
                Duration::from_secs(5)
            ),
            "B proceeds after {completion:?}"
        );
        assert_eq!(b_invoked.load(Ordering::SeqCst), 1);
        manager.shutdown();
        executor.shutdown().expect("shutdown");
    }
}

#[test]
fn queued_execution_host_timeout_fails_without_executing_the_handler() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor = open_executor(directory.path());
    let manager = manager(&executor);
    let a_id = insert_job(&executor);
    let (a_handler, a_started, a_release) = BlockingHandler::new(JobRunState::Completed);
    manager
        .register(&handle(a_id), Arc::new(a_handler), RESOURCES)
        .expect("register A");
    a_started
        .recv_timeout(Duration::from_secs(5))
        .expect("A holds resources");

    let b_id = insert_job(&executor);
    let (b_handler, b_invoked, b_cleanup) = CountingHandler::new();
    manager
        .register(&handle(b_id), Arc::new(b_handler), RESOURCES)
        .expect("register B");
    assert!(wait_until(
        || job_state(&executor, b_id) == JobRunState::Queued,
        Duration::from_secs(5)
    ));

    manager.notify_execution_host_stop(b_id, BackgroundOperationStopReason::ExecutionHostTimeout);
    assert!(wait_until(
        || job_state(&executor, b_id) == JobRunState::Failed,
        Duration::from_secs(5)
    ));
    assert_eq!(b_invoked.load(Ordering::SeqCst), 0);
    assert_eq!(b_cleanup.load(Ordering::SeqCst), 1);

    a_release.send(()).expect("release A");
    assert!(wait_until(
        || job_state(&executor, a_id) == JobRunState::Completed,
        Duration::from_secs(5)
    ));
    manager.shutdown();
    executor.shutdown().expect("shutdown");
}

#[test]
fn queued_execution_host_loss_fails_without_executing_the_handler() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor = open_executor(directory.path());
    let manager = manager(&executor);
    let a_id = insert_job(&executor);
    let (a_handler, a_started, a_release) = BlockingHandler::new(JobRunState::Completed);
    manager
        .register(&handle(a_id), Arc::new(a_handler), RESOURCES)
        .expect("register A");
    a_started
        .recv_timeout(Duration::from_secs(5))
        .expect("A holds resources");

    let b_id = insert_job(&executor);
    let (b_handler, b_invoked, b_cleanup) = CountingHandler::new();
    manager
        .register(&handle(b_id), Arc::new(b_handler), RESOURCES)
        .expect("register B");
    assert!(wait_until(
        || job_state(&executor, b_id) == JobRunState::Queued,
        Duration::from_secs(5)
    ));

    manager.notify_execution_host_stop(b_id, BackgroundOperationStopReason::ExecutionHostLost);
    assert!(wait_until(
        || job_state(&executor, b_id) == JobRunState::Failed,
        Duration::from_secs(5)
    ));
    assert_eq!(b_invoked.load(Ordering::SeqCst), 0);
    assert_eq!(b_cleanup.load(Ordering::SeqCst), 1);

    a_release.send(()).expect("release A");
    assert!(wait_until(
        || job_state(&executor, a_id) == JobRunState::Completed,
        Duration::from_secs(5)
    ));
    manager.shutdown();
    executor.shutdown().expect("shutdown");
}

#[test]
fn accepted_cancellation_wins_when_host_stop_already_exists() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor = open_executor(directory.path());
    let manager = manager(&executor);
    let a_id = insert_job(&executor);
    let (a_handler, a_started, a_release) = BlockingHandler::new(JobRunState::Completed);
    manager
        .register(&handle(a_id), Arc::new(a_handler), RESOURCES)
        .expect("register A");
    a_started
        .recv_timeout(Duration::from_secs(5))
        .expect("A holds resources");

    let b_id = insert_job(&executor);
    let (b_handler, b_invoked, b_cleanup) = CountingHandler::new();
    manager
        .register(&handle(b_id), Arc::new(b_handler), RESOURCES)
        .expect("register B");
    assert!(wait_until(
        || job_state(&executor, b_id) == JobRunState::Queued,
        Duration::from_secs(5)
    ));

    manager.notify_execution_host_stop(b_id, BackgroundOperationStopReason::ExecutionHostLost);
    manager.notify_cancellation(b_id);
    assert!(wait_until(
        || job_state(&executor, b_id) == JobRunState::Cancelled,
        Duration::from_secs(5)
    ));
    assert_eq!(b_invoked.load(Ordering::SeqCst), 0);
    assert_eq!(b_cleanup.load(Ordering::SeqCst), 1);

    a_release.send(()).expect("release A");
    assert!(wait_until(
        || job_state(&executor, a_id) == JobRunState::Completed,
        Duration::from_secs(5)
    ));
    manager.shutdown();
    executor.shutdown().expect("shutdown");
}

#[test]
fn host_stop_for_unknown_run_is_an_idempotent_no_op() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor = open_executor(directory.path());
    let manager = manager(&executor);
    let job_run_id = insert_job(&executor);
    let (handler, started, release) = BlockingHandler::new(JobRunState::Completed);
    manager
        .register(&handle(job_run_id), Arc::new(handler), RESOURCES)
        .expect("register run");
    started
        .recv_timeout(Duration::from_secs(5))
        .expect("run starts");

    let unknown_id = insert_job(&executor);
    manager.notify_execution_host_stop(
        unknown_id,
        BackgroundOperationStopReason::ExecutionHostTimeout,
    );
    release.send(()).expect("release run");
    assert!(wait_until(
        || job_state(&executor, job_run_id) == JobRunState::Completed,
        Duration::from_secs(5)
    ));
    manager.shutdown();
    executor.shutdown().expect("shutdown");
}

#[test]
fn registration_removes_the_run_when_worker_spawn_fails() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor = open_executor(directory.path());
    let manager = manager(&executor);
    manager.fail_next_spawn_for_tests();
    let job_run_id = insert_job(&executor);
    let (handler, _, _) = CountingHandler::new();
    let result = manager.register(&handle(job_run_id), Arc::new(handler), RESOURCES);
    assert!(
        result.is_err(),
        "spawn failure surfaces as a registration failure"
    );
    assert_eq!(
        manager.active_len_for_tests(),
        0,
        "no orphan in-memory ownership"
    );
    assert_eq!(manager.pending_len_for_tests(), 0, "no stale pending entry");
    manager.shutdown();
    executor.shutdown().expect("shutdown");
}
