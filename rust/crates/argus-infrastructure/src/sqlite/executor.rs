//! Bounded one-worker SQLite executor.

use std::any::Any;
use std::path::{Path, PathBuf};
#[cfg(feature = "test-support")]
use std::sync::Condvar;
#[cfg(feature = "test-support")]
use std::sync::atomic::AtomicUsize;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, SyncSender};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle, ThreadId};
#[cfg(feature = "test-support")]
use std::time::{Duration, Instant};

use argus_application::{
    ApplicationPortError, OperationContext, PersistenceError, UnitOfWorkFactory,
};
#[cfg(feature = "test-support")]
use rusqlite::InterruptHandle;
#[cfg(feature = "test-support")]
use rusqlite::trace::{TraceEvent, TraceEventCodes};
use rusqlite::{Connection, OpenFlags};

use super::connection::SqliteConnection;
use super::errors::{SqliteExecutorError, SqliteOperationError, operation_error};
use super::migrations::{MigrationRegistry, MigrationSummary, apply_migrations};
use super::unit_of_work::SqliteUnitOfWork;

/// Default bounded queue capacity for the database worker.
pub const DEFAULT_QUEUE_CAPACITY: usize = 32;

#[cfg(feature = "test-support")]
const NORMAL_BUSY_TIMEOUT: Duration = Duration::from_millis(5_000);

type JobResult = Result<Box<dyn Any + Send>, SqliteExecutorError>;
type Job = Box<dyn FnOnce(&mut Connection, OperationContext) -> JobResult + Send + 'static>;

struct WorkItem {
    context: OperationContext,
    job: Job,
    response: mpsc::Sender<JobResult>,
}

enum Command {
    Work(WorkItem),
}

struct ExecutorState {
    sender: Option<SyncSender<Command>>,
    join: Option<JoinHandle<()>>,
    worker_id: Option<ThreadId>,
}

struct SharedExecutor {
    state: Mutex<ExecutorState>,
    /// Serializes admission with shutdown. The lock is held through the
    /// bounded send so every admitted item is either accepted and drained or
    /// rejected before shutdown closes admission.
    admission: Mutex<()>,
    closed: AtomicBool,
    poisoned: AtomicBool,
    disconnected: AtomicBool,
    #[cfg(feature = "test-support")]
    attempted: std::sync::atomic::AtomicUsize,
    #[cfg(feature = "test-support")]
    accepted: std::sync::atomic::AtomicUsize,
    /// Tracks ordinary work still waiting for or running on the worker.
    #[cfg(feature = "test-support")]
    ordinary_in_flight: AtomicUsize,
    #[cfg(feature = "test-support")]
    observer_in_flight: AtomicBool,
    #[cfg(feature = "test-support")]
    test_progress: Mutex<()>,
    #[cfg(feature = "test-support")]
    test_progress_notify: Condvar,
}

#[cfg(feature = "test-support")]
struct OrdinaryWorkGuard(Arc<SharedExecutor>);

#[cfg(feature = "test-support")]
impl Drop for OrdinaryWorkGuard {
    fn drop(&mut self) {
        self.0.ordinary_in_flight.fetch_sub(1, Ordering::AcqRel);
    }
}

#[cfg(feature = "test-support")]
enum ObserverCancellationState {
    Queued,
    Running(InterruptHandle),
    Retiring,
    Cancelled,
    Finished,
}

#[cfg(feature = "test-support")]
type ObserverProgressHook = Arc<dyn Fn() + Send + Sync>;

/// Controls cancellation for one host-side observer database operation.
///
/// The handle is available only with `test-support`. Cancellation affects the
/// operation while it is queued or running and cannot interrupt later work.
/// A SQLite progress check also catches cancellation just before the first
/// statement starts, when there is no active statement for `interrupt` to stop.
#[cfg(feature = "test-support")]
#[doc(hidden)]
#[derive(Clone)]
pub struct ObserverCancellationHandle {
    state: Arc<Mutex<ObserverCancellationState>>,
    cancelled: Arc<AtomicBool>,
    progress_hook: Arc<Mutex<Option<ObserverProgressHook>>>,
}

#[cfg(feature = "test-support")]
impl ObserverCancellationHandle {
    /// Creates a cancellation handle for one observer operation.
    pub fn new() -> Self {
        Self {
            state: Arc::new(Mutex::new(ObserverCancellationState::Queued)),
            cancelled: Arc::new(AtomicBool::new(false)),
            progress_hook: Arc::new(Mutex::new(None)),
        }
    }

    /// Installs a hook called while SQLite runs an observer statement.
    ///
    /// Tests use the hook to coordinate cancellation without timing sleeps.
    #[doc(hidden)]
    pub fn with_progress_hook_for_tests(&self, hook: impl Fn() + Send + Sync + 'static) {
        if let Ok(mut progress_hook) = self.progress_hook.lock() {
            *progress_hook = Some(Arc::new(hook));
        }
    }

    /// Reports whether cancellation has been recorded for this operation.
    #[doc(hidden)]
    pub fn is_cancelled_for_tests(&self) -> bool {
        self.cancelled.load(Ordering::Acquire)
    }

    fn progress_hook(&self) -> Option<ObserverProgressHook> {
        self.progress_hook.lock().ok()?.clone()
    }

    /// Cancels the operation if it has not finished.
    ///
    /// Returns `true` when cancellation was recorded and `false` after the
    /// operation has already been cancelled or retired.
    pub fn cancel(&self) -> Result<bool, SqliteExecutorError> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| SqliteExecutorError::Internal)?;
        match &*state {
            ObserverCancellationState::Queued => {
                self.cancelled.store(true, Ordering::Release);
                *state = ObserverCancellationState::Cancelled;
                Ok(true)
            }
            ObserverCancellationState::Running(interrupt) => {
                // Keep this lock until the interrupt call completes. The
                // worker cannot retire this handle or start the next item
                // while cancellation targets the current connection.
                self.cancelled.store(true, Ordering::Release);
                interrupt.interrupt();
                *state = ObserverCancellationState::Cancelled;
                Ok(true)
            }
            ObserverCancellationState::Retiring
            | ObserverCancellationState::Cancelled
            | ObserverCancellationState::Finished => Ok(false),
        }
    }

    fn activate(
        &self,
        interrupt: InterruptHandle,
    ) -> Result<ObserverOperationGuard, SqliteExecutorError> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| SqliteExecutorError::Internal)?;
        match &*state {
            ObserverCancellationState::Queued => {
                *state = ObserverCancellationState::Running(interrupt);
                Ok(ObserverOperationGuard {
                    cancellation: self.clone(),
                })
            }
            ObserverCancellationState::Cancelled => Err(SqliteExecutorError::ObserverCancelled),
            ObserverCancellationState::Running(_)
            | ObserverCancellationState::Retiring
            | ObserverCancellationState::Finished => Err(SqliteExecutorError::Internal),
        }
    }

    fn retire(&self) -> Result<bool, SqliteExecutorError> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| SqliteExecutorError::Internal)?;
        match &*state {
            ObserverCancellationState::Running(_) => {
                *state = ObserverCancellationState::Retiring;
                Ok(false)
            }
            ObserverCancellationState::Cancelled => Ok(true),
            ObserverCancellationState::Queued
            | ObserverCancellationState::Retiring
            | ObserverCancellationState::Finished => Err(SqliteExecutorError::Internal),
        }
    }

    fn finish(&self) {
        if let Ok(mut state) = self.state.lock()
            && matches!(
                &*state,
                ObserverCancellationState::Queued
                    | ObserverCancellationState::Running(_)
                    | ObserverCancellationState::Retiring
            )
        {
            *state = ObserverCancellationState::Finished;
        }
    }
}

#[cfg(feature = "test-support")]
impl Default for ObserverCancellationHandle {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(feature = "test-support")]
struct ObserverOperationGuard {
    cancellation: ObserverCancellationHandle,
}

#[cfg(feature = "test-support")]
impl ObserverOperationGuard {
    fn retire(&self) -> Result<bool, SqliteExecutorError> {
        self.cancellation.retire()
    }
}

#[cfg(feature = "test-support")]
impl Drop for ObserverOperationGuard {
    fn drop(&mut self) {
        self.cancellation.finish();
    }
}

#[cfg(feature = "test-support")]
struct ObserverSubmissionGuard {
    shared: Arc<SharedExecutor>,
    cancellation: ObserverCancellationHandle,
    accepted: bool,
    reserved: bool,
}

#[cfg(feature = "test-support")]
impl Drop for ObserverSubmissionGuard {
    fn drop(&mut self) {
        if !self.accepted {
            self.cancellation.finish();
        }
        if self.reserved {
            self.shared
                .observer_in_flight
                .store(false, Ordering::Release);
        }
    }
}

/// The owned, cloneable handle for one dedicated SQLite worker thread.
#[derive(Clone)]
pub struct SqliteDatabaseExecutor {
    shared: Arc<SharedExecutor>,
    migration_summary: MigrationSummary,
    library_view_key: Option<[u8; 32]>,
}

thread_local! {
    static IN_DATABASE_WORKER: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

#[cfg(feature = "test-support")]
thread_local! {
    static TEST_SQL_STATEMENT_COUNT: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

#[cfg(feature = "test-support")]
fn count_test_sql_statement(event: TraceEvent<'_>) {
    if matches!(event, TraceEvent::Stmt(_, _)) {
        TEST_SQL_STATEMENT_COUNT.with(|count| count.set(count.get().saturating_add(1)));
    }
}

impl SqliteDatabaseExecutor {
    /// Opens/configures/migrates one database using the embedded registry.
    pub fn open(path: impl AsRef<Path>) -> Result<Self, SqliteExecutorError> {
        Self::open_with_registry(path, MigrationRegistry::embedded())
    }

    /// Opens/configures/migrates one database with an explicit queue capacity.
    pub fn open_with_capacity(
        path: impl AsRef<Path>,
        capacity: usize,
    ) -> Result<Self, SqliteExecutorError> {
        Self::open_with_capacity_and_registry(path, capacity, MigrationRegistry::embedded())
    }

    /// Opens/configures/migrates one database with a custom migration registry.
    pub fn open_with_registry(
        path: impl AsRef<Path>,
        registry: MigrationRegistry,
    ) -> Result<Self, SqliteExecutorError> {
        Self::open_with_capacity_and_registry(path, DEFAULT_QUEUE_CAPACITY, registry)
    }

    /// Opens the database with the process key used to authenticate Library views.
    pub fn open_with_capacity_and_view_key(
        path: impl AsRef<Path>,
        capacity: usize,
        library_view_key: [u8; 32],
    ) -> Result<Self, SqliteExecutorError> {
        Self::open_with_capacity_and_registry_and_view_key(
            path,
            capacity,
            MigrationRegistry::embedded(),
            Some(library_view_key),
        )
    }

    fn open_with_capacity_and_registry(
        path: impl AsRef<Path>,
        capacity: usize,
        registry: MigrationRegistry,
    ) -> Result<Self, SqliteExecutorError> {
        Self::open_with_capacity_and_registry_and_view_key(path, capacity, registry, None)
    }

    fn open_with_capacity_and_registry_and_view_key(
        path: impl AsRef<Path>,
        capacity: usize,
        registry: MigrationRegistry,
        library_view_key: Option<[u8; 32]>,
    ) -> Result<Self, SqliteExecutorError> {
        if capacity == 0 {
            return Err(SqliteExecutorError::Internal);
        }
        let path = path.as_ref().to_path_buf();
        if let Some(parent) = path
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
        {
            std::fs::create_dir_all(parent).map_err(|_| SqliteExecutorError::DatabaseOpenFailed)?;
        }
        let (sender, receiver) = mpsc::sync_channel(capacity);
        let (startup_sender, startup_receiver) = mpsc::channel();
        let shared = Arc::new(SharedExecutor {
            state: Mutex::new(ExecutorState {
                sender: Some(sender),
                join: None,
                worker_id: None,
            }),
            admission: Mutex::new(()),
            closed: AtomicBool::new(false),
            poisoned: AtomicBool::new(false),
            disconnected: AtomicBool::new(false),
            #[cfg(feature = "test-support")]
            attempted: std::sync::atomic::AtomicUsize::new(0),
            #[cfg(feature = "test-support")]
            accepted: std::sync::atomic::AtomicUsize::new(0),
            #[cfg(feature = "test-support")]
            ordinary_in_flight: AtomicUsize::new(0),
            #[cfg(feature = "test-support")]
            observer_in_flight: AtomicBool::new(false),
            #[cfg(feature = "test-support")]
            test_progress: Mutex::new(()),
            #[cfg(feature = "test-support")]
            test_progress_notify: Condvar::new(),
        });
        let shared_for_worker = Arc::clone(&shared);
        let worker_path = path.clone();
        let join = thread::Builder::new()
            .name("argus-sqlite-worker".into())
            .spawn(move || {
                worker_main(
                    shared_for_worker,
                    worker_path,
                    receiver,
                    startup_sender,
                    registry,
                )
            })
            .map_err(|_| SqliteExecutorError::DatabaseOpenFailed)?;
        {
            let mut state = shared
                .state
                .lock()
                .map_err(|_| SqliteExecutorError::Internal)?;
            state.join = Some(join);
        }
        match startup_receiver.recv() {
            Ok(Ok(summary)) => Ok(Self {
                shared,
                migration_summary: summary,
                library_view_key,
            }),
            Ok(Err(error)) => {
                let executor = Self {
                    shared,
                    migration_summary: empty_summary(),
                    library_view_key,
                };
                let _ = executor.shutdown();
                Err(error)
            }
            Err(_) => {
                let executor = Self {
                    shared,
                    migration_summary: empty_summary(),
                    library_view_key,
                };
                let _ = executor.shutdown();
                Err(SqliteExecutorError::DatabaseOpenFailed)
            }
        }
    }

    /// Returns the migration summary produced during startup.
    pub fn migration_summary(&self) -> &MigrationSummary {
        &self.migration_summary
    }

    #[cfg(feature = "test-support")]
    #[doc(hidden)]
    fn attempted_work_count_for_tests(&self) -> usize {
        self.shared
            .attempted
            .load(std::sync::atomic::Ordering::Acquire)
    }

    #[cfg(feature = "test-support")]
    #[doc(hidden)]
    fn accepted_work_count_for_tests(&self) -> usize {
        self.shared
            .accepted
            .load(std::sync::atomic::Ordering::Acquire)
    }

    #[cfg(feature = "test-support")]
    #[doc(hidden)]
    pub fn wait_for_admitted_for_tests(&self, expected: usize, timeout: Duration) -> bool {
        self.wait_for_test_condition(timeout, || self.accepted_work_count_for_tests() >= expected)
    }

    #[cfg(feature = "test-support")]
    #[doc(hidden)]
    pub fn wait_for_attempted_for_tests(&self, expected: usize, timeout: Duration) -> bool {
        self.wait_for_test_condition(timeout, || {
            self.attempted_work_count_for_tests() >= expected
        })
    }

    #[cfg(feature = "test-support")]
    #[doc(hidden)]
    fn admission_closed_for_tests(&self) -> bool {
        self.shared.closed.load(Ordering::Acquire)
    }

    #[cfg(feature = "test-support")]
    #[doc(hidden)]
    pub fn wait_for_admission_closed_for_tests(&self, timeout: Duration) -> bool {
        self.wait_for_test_condition(timeout, || self.admission_closed_for_tests())
    }

    #[cfg(feature = "test-support")]
    #[doc(hidden)]
    pub fn wait_for_disconnected_for_tests(&self, timeout: Duration) -> bool {
        self.wait_for_test_condition(timeout, || self.shared.disconnected.load(Ordering::Acquire))
    }

    /// Drops the worker's command sender to exercise the stable disconnect
    /// mapping without adding worker-control behavior to production callers.
    #[cfg(feature = "test-support")]
    #[doc(hidden)]
    pub fn disconnect_worker_for_tests(&self) {
        if let Ok(mut state) = self.shared.state.lock() {
            state.sender.take();
        }
        self.notify_test_progress();
    }

    /// Executes a callback on the dedicated database thread.
    #[cfg_attr(not(feature = "test-support"), allow(dead_code))]
    pub(crate) fn with_connection<T, F>(
        &self,
        context: OperationContext,
        callback: F,
    ) -> Result<T, SqliteExecutorError>
    where
        T: Send + 'static,
        F: FnOnce(&mut SqliteConnection<'_>) -> Result<T, SqliteOperationError> + Send + 'static,
    {
        self.submit(context, callback)
    }

    /// Executes a raw SQLite callback for infrastructure integration tests.
    ///
    /// This surface is available only with the `test-support` feature and is
    /// intentionally absent from normal production builds.
    #[cfg(feature = "test-support")]
    #[doc(hidden)]
    pub fn with_connection_for_tests<T, F>(
        &self,
        context: OperationContext,
        callback: F,
    ) -> Result<T, SqliteExecutorError>
    where
        T: Send + 'static,
        F: FnOnce(&mut SqliteConnection<'_>) -> Result<T, SqliteOperationError> + Send + 'static,
    {
        self.with_connection(context, callback)
    }

    /// Runs a host-side observer callback with bounded queueing and cancellation.
    ///
    /// The observer operation uses a zero-millisecond SQLite busy timeout and
    /// restores the normal five-second timeout before returning. This method
    /// and its cancellation handle are compiled only with `test-support`. A
    /// progress check covers cancellation that races with the first statement.
    #[cfg(feature = "test-support")]
    #[doc(hidden)]
    pub fn with_observer_connection_for_tests<T, F>(
        &self,
        context: OperationContext,
        cancellation: ObserverCancellationHandle,
        callback: F,
    ) -> Result<T, SqliteExecutorError>
    where
        T: Send + 'static,
        F: FnOnce(&mut SqliteConnection<'_>) -> Result<T, SqliteOperationError> + Send + 'static,
    {
        let worker_cancellation = cancellation.clone();
        let job: Job = Box::new(move |connection, operation_context| {
            let operation = worker_cancellation.activate(connection.get_interrupt_handle())?;
            if connection.busy_timeout(Duration::ZERO).is_err() {
                let cancelled = operation.retire();
                let restored = connection.busy_timeout(NORMAL_BUSY_TIMEOUT);
                if restored.is_err() {
                    return Err(SqliteExecutorError::Internal);
                }
                if cancelled? {
                    return Err(SqliteExecutorError::ObserverCancelled);
                }
                return Err(SqliteExecutorError::Internal);
            }

            let progress_cancelled = Arc::clone(&worker_cancellation.cancelled);
            let progress_hook = worker_cancellation.progress_hook();
            let progress_interval = if progress_hook.is_some() { 1 } else { 1_000 };
            if connection
                .progress_handler(
                    progress_interval,
                    Some(move || {
                        if let Some(hook) = &progress_hook {
                            hook();
                        }
                        progress_cancelled.load(Ordering::Acquire)
                    }),
                )
                .is_err()
            {
                let cancelled = operation.retire();
                let handler_cleared = connection.progress_handler(0, None::<fn() -> bool>);
                let restored = connection.busy_timeout(NORMAL_BUSY_TIMEOUT);
                if handler_cleared.is_err() || restored.is_err() {
                    return Err(SqliteExecutorError::Internal);
                }
                if cancelled? {
                    return Err(SqliteExecutorError::ObserverCancelled);
                }
                return Err(SqliteExecutorError::Internal);
            }

            let operation_result = {
                let mut scoped_connection = SqliteConnection::new(connection, operation_context);
                callback(&mut scoped_connection)
            };
            let cancelled = operation.retire();
            let handler_cleared = connection.progress_handler(0, None::<fn() -> bool>);
            let restored = connection.busy_timeout(NORMAL_BUSY_TIMEOUT);
            if handler_cleared.is_err() || restored.is_err() {
                return Err(SqliteExecutorError::Internal);
            }
            if cancelled? {
                return Err(SqliteExecutorError::ObserverCancelled);
            }
            operation_result
                .map(|value| Box::new(value) as Box<dyn Any + Send>)
                .map_err(|error| match error {
                    SqliteOperationError::Locked => SqliteExecutorError::ObserverBusy,
                    SqliteOperationError::Constraint | SqliteOperationError::Failed => {
                        SqliteExecutorError::Internal
                    }
                    SqliteOperationError::Application(error) => {
                        SqliteExecutorError::ApplicationCallback(error)
                    }
                })
        });
        self.submit_observer_inner(context, cancellation, job)
    }

    /// Runs a transaction-scoped callback through observer cancellation.
    ///
    /// Use this test-only helper for reads and leave the unit of work
    /// uncommitted. Dropping it rolls back the deferred transaction.
    #[cfg(feature = "test-support")]
    #[doc(hidden)]
    pub fn with_observer_unit_of_work_for_tests<T, F>(
        &self,
        context: OperationContext,
        cancellation: ObserverCancellationHandle,
        callback: F,
    ) -> Result<T, SqliteExecutorError>
    where
        T: Send + 'static,
        F: for<'scope> FnOnce(SqliteUnitOfWork<'scope>) -> Result<T, ApplicationPortError>
            + Send
            + 'static,
    {
        let library_view_key = self.library_view_key;
        self.with_observer_connection_for_tests(context, cancellation, move |connection| {
            let operation_context = connection.operation_context().clone();
            let transaction = connection
                .connection
                .transaction_with_behavior(rusqlite::TransactionBehavior::Deferred)
                .map_err(|error| operation_error(&error))?;
            let work = SqliteUnitOfWork::new_with_library_view_key(
                transaction,
                operation_context,
                library_view_key,
            );
            callback(work).map_err(SqliteOperationError::Application)
        })
    }

    /// Executes one transaction-scoped callback on the database worker.
    ///
    /// The callback owns the transaction scope. Returning without calling
    /// `commit` or `rollback` drops that scope and therefore rolls it back;
    /// there is no implicit commit on a successful callback result.
    pub fn with_unit_of_work<T, F>(
        &self,
        context: OperationContext,
        callback: F,
    ) -> Result<T, SqliteExecutorError>
    where
        T: Send + 'static,
        F: for<'scope> FnOnce(SqliteUnitOfWork<'scope>) -> Result<T, ApplicationPortError>
            + Send
            + 'static,
    {
        let library_view_key = self.library_view_key;
        self.submit_job(
            context,
            Box::new(
                move |connection: &mut Connection, operation_context: OperationContext| {
                    let transaction = connection
                        .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)
                        .map_err(|error| match operation_error(&error) {
                            SqliteOperationError::Locked => SqliteExecutorError::DatabaseLocked,
                            _ => SqliteExecutorError::Internal,
                        })?;
                    let work = SqliteUnitOfWork::new_with_library_view_key(
                        transaction,
                        operation_context,
                        library_view_key,
                    );
                    callback(work)
                        .map(|value| Box::new(value) as Box<dyn Any + Send>)
                        .map_err(SqliteExecutorError::ApplicationCallback)
                },
            ),
        )
    }

    /// Runs a transaction-scoped callback and returns its SQLite statement
    /// count for scale tests. The trace hook is installed only for this
    /// test-support operation and is never part of the production API.
    #[cfg(feature = "test-support")]
    #[doc(hidden)]
    pub fn with_unit_of_work_and_statement_count_for_tests<T, F>(
        &self,
        context: OperationContext,
        callback: F,
    ) -> Result<(T, usize), SqliteExecutorError>
    where
        T: Send + 'static,
        F: for<'scope> FnOnce(SqliteUnitOfWork<'scope>) -> Result<T, ApplicationPortError>
            + Send
            + 'static,
    {
        let library_view_key = self.library_view_key;
        let (value, statement_count): (T, usize) = self.submit_job(
            context,
            Box::new(move |connection, operation_context| {
                TEST_SQL_STATEMENT_COUNT.with(|count| count.set(0));
                connection.trace_v2(
                    TraceEventCodes::SQLITE_TRACE_STMT,
                    Some(count_test_sql_statement),
                );
                let transaction = connection
                    .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)
                    .map_err(|error| match operation_error(&error) {
                        SqliteOperationError::Locked => SqliteExecutorError::DatabaseLocked,
                        _ => SqliteExecutorError::Internal,
                    })?;
                let work = SqliteUnitOfWork::new_with_library_view_key(
                    transaction,
                    operation_context,
                    library_view_key,
                );
                let result = callback(work)
                    .map(|value| {
                        let statement_count = TEST_SQL_STATEMENT_COUNT.with(std::cell::Cell::get);
                        Box::new((value, statement_count)) as Box<dyn Any + Send>
                    })
                    .map_err(SqliteExecutorError::ApplicationCallback);
                connection.trace_v2(TraceEventCodes::SQLITE_TRACE_STMT, None);
                result
            }),
        )?;
        Ok((value, statement_count))
    }

    /// Runs bounded backend I/O on the dedicated worker without opening a
    /// SQLite write transaction.
    ///
    /// Provider HTTP and artwork-object reads use this seam so the caller can
    /// preserve the invariant that external I/O never occurs while a database
    /// write transaction is held.
    pub fn execute_on_worker<T, F>(
        &self,
        context: OperationContext,
        callback: F,
    ) -> Result<T, SqliteExecutorError>
    where
        T: Send + 'static,
        F: FnOnce() -> Result<T, SqliteExecutorError> + Send + 'static,
    {
        self.submit_job(
            context,
            Box::new(move |_connection, _operation_context| {
                callback().map(|value| Box::new(value) as Box<dyn Any + Send>)
            }),
        )
    }

    /// Closes admission, drains accepted work, retires the worker connection,
    /// and joins it. Repeated calls are deterministic and harmless.
    pub fn shutdown(&self) -> Result<(), SqliteExecutorError> {
        if IN_DATABASE_WORKER.with(std::cell::Cell::get) {
            return Err(SqliteExecutorError::ReentrantSubmission);
        }
        self.shared.closed.store(true, Ordering::Release);
        #[cfg(feature = "test-support")]
        self.notify_test_progress();
        let _admission = self
            .shared
            .admission
            .lock()
            .map_err(|_| SqliteExecutorError::Internal)?;
        let join = {
            let mut state = self
                .shared
                .state
                .lock()
                .map_err(|_| SqliteExecutorError::Internal)?;
            state.sender.take();
            state.join.take()
        };
        drop(_admission);
        if let Some(join) = join {
            join.join().map_err(|_| SqliteExecutorError::Internal)?;
        }
        Ok(())
    }

    #[cfg_attr(not(feature = "test-support"), allow(dead_code))]
    fn submit<T, F>(&self, context: OperationContext, callback: F) -> Result<T, SqliteExecutorError>
    where
        T: Send + 'static,
        F: FnOnce(&mut SqliteConnection<'_>) -> Result<T, SqliteOperationError> + Send + 'static,
    {
        self.submit_inner(context, callback_job(callback))
    }

    fn submit_job<T>(&self, context: OperationContext, job: Job) -> Result<T, SqliteExecutorError>
    where
        T: Send + 'static,
    {
        self.submit_inner(context, job)
    }

    fn submit_inner<T>(&self, context: OperationContext, job: Job) -> Result<T, SqliteExecutorError>
    where
        T: Send + 'static,
    {
        if IN_DATABASE_WORKER.with(std::cell::Cell::get) {
            return Err(SqliteExecutorError::ReentrantSubmission);
        }

        // Poison takes precedence over shutdown so callers observing a panic
        // generation receive the stable poison result rather than a channel
        // disconnect or incidental shutdown result.
        if self.shared.poisoned.load(Ordering::Acquire) {
            return Err(SqliteExecutorError::Poisoned);
        }
        if self.shared.closed.load(Ordering::Acquire) {
            return Err(SqliteExecutorError::Shutdown);
        }
        if self.shared.disconnected.load(Ordering::Acquire) {
            return Err(SqliteExecutorError::Disconnected);
        }

        let _admission = self
            .shared
            .admission
            .lock()
            .map_err(|_| SqliteExecutorError::Internal)?;
        if self.shared.poisoned.load(Ordering::Acquire) {
            return Err(SqliteExecutorError::Poisoned);
        }
        if self.shared.closed.load(Ordering::Acquire) {
            return Err(SqliteExecutorError::Shutdown);
        }
        if self.shared.disconnected.load(Ordering::Acquire) {
            return Err(SqliteExecutorError::Disconnected);
        }
        let worker_id = {
            let state = self
                .shared
                .state
                .lock()
                .map_err(|_| SqliteExecutorError::Internal)?;
            if state.sender.is_none() {
                return if self.shared.poisoned.load(Ordering::Acquire) {
                    Err(SqliteExecutorError::Poisoned)
                } else if self.shared.closed.load(Ordering::Acquire) {
                    Err(SqliteExecutorError::Shutdown)
                } else {
                    Err(SqliteExecutorError::Disconnected)
                };
            }
            state.worker_id
        };
        if worker_id.is_some_and(|id| id == thread::current().id()) {
            return Err(SqliteExecutorError::ReentrantSubmission);
        }
        #[cfg(feature = "test-support")]
        let job = {
            self.shared
                .ordinary_in_flight
                .fetch_add(1, Ordering::AcqRel);
            let completion = OrdinaryWorkGuard(Arc::clone(&self.shared));
            Box::new(
                move |connection: &mut Connection, operation_context: OperationContext| {
                    let _completion = completion;
                    job(connection, operation_context)
                },
            ) as Job
        };
        let (response_sender, response_receiver) = mpsc::channel();
        let item = WorkItem {
            context,
            job,
            response: response_sender,
        };
        #[cfg(feature = "test-support")]
        {
            self.shared.attempted.fetch_add(1, Ordering::AcqRel);
            self.notify_test_progress();
        }
        let sender = {
            let state = self
                .shared
                .state
                .lock()
                .map_err(|_| SqliteExecutorError::Internal)?;
            state
                .sender
                .as_ref()
                .ok_or_else(|| {
                    if self.shared.poisoned.load(Ordering::Acquire) {
                        SqliteExecutorError::Poisoned
                    } else if self.shared.closed.load(Ordering::Acquire) {
                        SqliteExecutorError::Shutdown
                    } else {
                        SqliteExecutorError::Disconnected
                    }
                })?
                .clone()
        };

        // This is deliberately blocking backpressure. Holding admission over
        // the send makes shutdown's linearization point unambiguous.
        if sender.send(Command::Work(item)).is_err() {
            return if self.shared.poisoned.load(Ordering::Acquire) {
                Err(SqliteExecutorError::Poisoned)
            } else if self.shared.closed.load(Ordering::Acquire) {
                Err(SqliteExecutorError::Shutdown)
            } else {
                Err(SqliteExecutorError::Disconnected)
            };
        }
        #[cfg(feature = "test-support")]
        {
            self.shared.accepted.fetch_add(1, Ordering::AcqRel);
            self.notify_test_progress();
        }
        drop(_admission);

        let response = response_receiver.recv();
        let result = response.map_err(|_| {
            if self.shared.poisoned.load(Ordering::Acquire) {
                SqliteExecutorError::Poisoned
            } else if self.shared.closed.load(Ordering::Acquire) {
                SqliteExecutorError::Shutdown
            } else {
                SqliteExecutorError::Disconnected
            }
        })??;
        result
            .downcast::<T>()
            .map(|value| *value)
            .map_err(|_| SqliteExecutorError::Internal)
    }

    #[cfg(feature = "test-support")]
    fn submit_observer_inner<T>(
        &self,
        context: OperationContext,
        cancellation: ObserverCancellationHandle,
        job: Job,
    ) -> Result<T, SqliteExecutorError>
    where
        T: Send + 'static,
    {
        let mut submission = ObserverSubmissionGuard {
            shared: Arc::clone(&self.shared),
            cancellation,
            accepted: false,
            reserved: false,
        };
        if IN_DATABASE_WORKER.with(std::cell::Cell::get) {
            return Err(SqliteExecutorError::ReentrantSubmission);
        }
        self.shared.attempted.fetch_add(1, Ordering::AcqRel);
        self.notify_test_progress();
        if submission.cancellation.cancelled.load(Ordering::Acquire) {
            return Err(SqliteExecutorError::ObserverCancelled);
        }
        if self.shared.poisoned.load(Ordering::Acquire) {
            return Err(SqliteExecutorError::Poisoned);
        }
        if self.shared.closed.load(Ordering::Acquire) {
            return Err(SqliteExecutorError::Shutdown);
        }
        if self.shared.disconnected.load(Ordering::Acquire) {
            return Err(SqliteExecutorError::Disconnected);
        }

        let _admission = match self.shared.admission.try_lock() {
            Ok(admission) => admission,
            Err(std::sync::TryLockError::WouldBlock) => {
                return Err(SqliteExecutorError::ObserverBusy);
            }
            Err(std::sync::TryLockError::Poisoned(_)) => {
                return Err(SqliteExecutorError::Internal);
            }
        };
        if self.shared.poisoned.load(Ordering::Acquire) {
            return Err(SqliteExecutorError::Poisoned);
        }
        if self.shared.closed.load(Ordering::Acquire) {
            return Err(SqliteExecutorError::Shutdown);
        }
        if self.shared.disconnected.load(Ordering::Acquire) {
            return Err(SqliteExecutorError::Disconnected);
        }
        if self.shared.ordinary_in_flight.load(Ordering::Acquire) != 0
            || self.shared.observer_in_flight.load(Ordering::Acquire)
        {
            return Err(SqliteExecutorError::ObserverBusy);
        }
        let sender = {
            let state = self
                .shared
                .state
                .lock()
                .map_err(|_| SqliteExecutorError::Internal)?;
            state.sender.as_ref().cloned().ok_or_else(|| {
                if self.shared.poisoned.load(Ordering::Acquire) {
                    SqliteExecutorError::Poisoned
                } else if self.shared.closed.load(Ordering::Acquire) {
                    SqliteExecutorError::Shutdown
                } else {
                    SqliteExecutorError::Disconnected
                }
            })?
        };
        let (response_sender, response_receiver) = mpsc::channel();
        let item = WorkItem {
            context,
            job,
            response: response_sender,
        };
        match sender.try_send(Command::Work(item)) {
            Ok(()) => {
                submission.accepted = true;
                submission.reserved = true;
                self.shared
                    .observer_in_flight
                    .store(true, Ordering::Release);
            }
            Err(mpsc::TrySendError::Full(_)) => {
                return Err(SqliteExecutorError::ObserverBusy);
            }
            Err(mpsc::TrySendError::Disconnected(_)) => {
                return if self.shared.poisoned.load(Ordering::Acquire) {
                    Err(SqliteExecutorError::Poisoned)
                } else if self.shared.closed.load(Ordering::Acquire) {
                    Err(SqliteExecutorError::Shutdown)
                } else {
                    Err(SqliteExecutorError::Disconnected)
                };
            }
        }
        self.shared.accepted.fetch_add(1, Ordering::AcqRel);
        self.notify_test_progress();
        drop(_admission);

        let response = response_receiver.recv();
        submission.cancellation.finish();
        let result = response.map_err(|_| {
            if self.shared.poisoned.load(Ordering::Acquire) {
                SqliteExecutorError::Poisoned
            } else if self.shared.closed.load(Ordering::Acquire) {
                SqliteExecutorError::Shutdown
            } else {
                SqliteExecutorError::Disconnected
            }
        })??;
        result
            .downcast::<T>()
            .map(|value| *value)
            .map_err(|_| SqliteExecutorError::Internal)
    }

    #[cfg(feature = "test-support")]
    fn notify_test_progress(&self) {
        notify_test_progress_shared(&self.shared);
    }

    #[cfg(feature = "test-support")]
    fn wait_for_test_condition<F>(&self, timeout: Duration, condition: F) -> bool
    where
        F: Fn() -> bool,
    {
        if condition() {
            return true;
        }
        let deadline = Instant::now() + timeout;
        let mut guard = match self.shared.test_progress.lock() {
            Ok(guard) => guard,
            Err(_) => return false,
        };
        loop {
            if condition() {
                return true;
            }
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return condition();
            }
            let result = self
                .shared
                .test_progress_notify
                .wait_timeout(guard, remaining);
            let (next_guard, timeout_result) = match result {
                Ok(result) => result,
                Err(_) => return false,
            };
            guard = next_guard;
            if timeout_result.timed_out() {
                return condition();
            }
        }
    }
}

#[cfg(feature = "test-support")]
fn notify_test_progress_shared(shared: &SharedExecutor) {
    if let Ok(_guard) = shared.test_progress.lock() {
        shared.test_progress_notify.notify_all();
    }
}

impl Drop for SqliteDatabaseExecutor {
    fn drop(&mut self) {
        if Arc::strong_count(&self.shared) == 1 {
            let _ = self.shutdown();
        }
    }
}

impl UnitOfWorkFactory for SqliteDatabaseExecutor {
    type Scope<'scope>
        = SqliteUnitOfWork<'scope>
    where
        Self: 'scope;

    fn execute<T, F>(
        &self,
        context: &OperationContext,
        operation: F,
    ) -> Result<T, ApplicationPortError>
    where
        T: Send + 'static,
        F: for<'scope> FnOnce(Self::Scope<'scope>) -> Result<T, ApplicationPortError>
            + Send
            + 'static,
    {
        self.with_unit_of_work(context.clone(), operation)
            .map_err(|error| match error {
                SqliteExecutorError::ApplicationCallback(application_error) => application_error,
                SqliteExecutorError::DatabaseOpenFailed
                | SqliteExecutorError::Shutdown
                | SqliteExecutorError::Poisoned
                | SqliteExecutorError::Disconnected => {
                    ApplicationPortError::Persistence(PersistenceError::Unavailable)
                }
                SqliteExecutorError::DatabaseLocked => {
                    ApplicationPortError::Persistence(PersistenceError::DatabaseLocked)
                }
                SqliteExecutorError::MigrationFailed { .. } => {
                    ApplicationPortError::Persistence(PersistenceError::MigrationFailed)
                }
                SqliteExecutorError::IncompatibleSchema => {
                    ApplicationPortError::Persistence(PersistenceError::CorruptOrIncompatible)
                }
                #[cfg(feature = "test-support")]
                SqliteExecutorError::ObserverBusy | SqliteExecutorError::ObserverCancelled => {
                    ApplicationPortError::Persistence(PersistenceError::Internal)
                }
                SqliteExecutorError::ReentrantSubmission | SqliteExecutorError::Internal => {
                    ApplicationPortError::Persistence(PersistenceError::Internal)
                }
            })
    }
}

#[cfg_attr(not(feature = "test-support"), allow(dead_code))]
fn callback_job<T, F>(callback: F) -> Job
where
    T: Send + 'static,
    F: FnOnce(&mut SqliteConnection<'_>) -> Result<T, SqliteOperationError> + Send + 'static,
{
    Box::new(move |connection, context| {
        let mut view = SqliteConnection::new(connection, context);
        callback(&mut view)
            .map(|value| Box::new(value) as Box<dyn Any + Send>)
            .map_err(|error| match error {
                SqliteOperationError::Locked => SqliteExecutorError::DatabaseLocked,
                SqliteOperationError::Constraint | SqliteOperationError::Failed => {
                    SqliteExecutorError::Internal
                }
                SqliteOperationError::Application(error) => {
                    SqliteExecutorError::ApplicationCallback(error)
                }
            })
    })
}

fn worker_main(
    shared: Arc<SharedExecutor>,
    path: PathBuf,
    receiver: Receiver<Command>,
    startup_sender: mpsc::Sender<Result<MigrationSummary, SqliteExecutorError>>,
    registry: MigrationRegistry,
) {
    IN_DATABASE_WORKER.with(|active| active.set(true));
    if let Ok(mut state) = shared.state.lock() {
        state.worker_id = Some(thread::current().id());
    }
    let connection = Connection::open_with_flags(
        &path,
        OpenFlags::SQLITE_OPEN_READ_WRITE | OpenFlags::SQLITE_OPEN_CREATE,
    );
    let mut connection = match connection {
        Ok(connection) => connection,
        Err(error) => {
            let _ = startup_sender.send(Err(
                if matches!(operation_error(&error), SqliteOperationError::Locked) {
                    SqliteExecutorError::DatabaseLocked
                } else {
                    SqliteExecutorError::DatabaseOpenFailed
                },
            ));
            IN_DATABASE_WORKER.with(|active| active.set(false));
            return;
        }
    };
    if let Err(error) = configure_connection(&mut connection) {
        let _ = startup_sender.send(Err(error));
        IN_DATABASE_WORKER.with(|active| active.set(false));
        return;
    }
    let migration_summary = match apply_migrations(&mut connection, &registry) {
        Ok(summary) => summary,
        Err(error) => {
            let _ = startup_sender.send(Err(error));
            IN_DATABASE_WORKER.with(|active| active.set(false));
            return;
        }
    };
    if let Err(error) = super::library_view::install_tracking(&connection) {
        let _ = startup_sender.send(Err(match operation_error(&error) {
            SqliteOperationError::Locked => SqliteExecutorError::DatabaseLocked,
            _ => SqliteExecutorError::Internal,
        }));
        IN_DATABASE_WORKER.with(|active| active.set(false));
        return;
    }
    let _ = startup_sender.send(Ok(migration_summary));
    while let Ok(Command::Work(item)) = receiver.recv() {
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            (item.job)(&mut connection, item.context)
        }));
        match result {
            Ok(result) => {
                let _ = item.response.send(result);
            }
            Err(_) => {
                shared.poisoned.store(true, Ordering::Release);
                shared.closed.store(true, Ordering::Release);
                #[cfg(feature = "test-support")]
                notify_test_progress_shared(&shared);
                let _ = item.response.send(Err(SqliteExecutorError::Poisoned));
                while let Ok(Command::Work(queued)) = receiver.try_recv() {
                    let _ = queued.response.send(Err(SqliteExecutorError::Poisoned));
                }
                break;
            }
        }
    }
    if !shared.closed.load(Ordering::Acquire) && !shared.poisoned.load(Ordering::Acquire) {
        shared.disconnected.store(true, Ordering::Release);
        #[cfg(feature = "test-support")]
        notify_test_progress_shared(&shared);
    }
    drop(connection);
    IN_DATABASE_WORKER.with(|active| active.set(false));
}

fn configure_connection(connection: &mut Connection) -> Result<(), SqliteExecutorError> {
    connection
        .execute_batch(
            "PRAGMA foreign_keys = ON;\nPRAGMA journal_mode = WAL;\nPRAGMA synchronous = NORMAL;\nPRAGMA busy_timeout = 5000;\nPRAGMA temp_store = MEMORY;",
        )
        .map_err(|error| match operation_error(&error) {
            SqliteOperationError::Locked => SqliteExecutorError::DatabaseLocked,
            _ => SqliteExecutorError::DatabaseOpenFailed,
        })?;
    let foreign_keys: i64 = connection
        .query_row("PRAGMA foreign_keys", [], |row| row.get(0))
        .map_err(|_| SqliteExecutorError::DatabaseOpenFailed)?;
    let journal_mode: String = connection
        .query_row("PRAGMA journal_mode", [], |row| row.get(0))
        .map_err(|_| SqliteExecutorError::DatabaseOpenFailed)?;
    let busy_timeout: i64 = connection
        .query_row("PRAGMA busy_timeout", [], |row| row.get(0))
        .map_err(|_| SqliteExecutorError::DatabaseOpenFailed)?;
    if foreign_keys != 1 || !journal_mode.eq_ignore_ascii_case("wal") || busy_timeout != 5_000 {
        return Err(SqliteExecutorError::DatabaseOpenFailed);
    }
    Ok(())
}

fn empty_summary() -> MigrationSummary {
    MigrationSummary {
        applied_count: 0,
        current_version: 0,
        outcome: super::migrations::MigrationOutcome::AlreadyCurrent,
    }
}
