//! Bounded one-worker SQLite executor.

use std::any::Any;
use std::path::{Path, PathBuf};
#[cfg(feature = "test-support")]
use std::sync::Condvar;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, SyncSender};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle, ThreadId};
#[cfg(feature = "test-support")]
use std::time::{Duration, Instant};

use argus_application::{
    ApplicationPortError, OperationContext, PersistenceError, UnitOfWorkFactory,
};
use rusqlite::{Connection, OpenFlags};

use super::connection::SqliteConnection;
use super::errors::{SqliteExecutorError, SqliteOperationError, operation_error};
use super::migrations::{MigrationRegistry, MigrationSummary, apply_migrations};
use super::unit_of_work::SqliteUnitOfWork;

/// Default bounded queue capacity for the database worker.
pub const DEFAULT_QUEUE_CAPACITY: usize = 32;

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
    #[cfg(feature = "test-support")]
    test_progress: Mutex<()>,
    #[cfg(feature = "test-support")]
    test_progress_notify: Condvar,
}

/// The owned, cloneable handle for one dedicated SQLite worker thread.
#[derive(Clone)]
pub struct SqliteDatabaseExecutor {
    shared: Arc<SharedExecutor>,
    migration_summary: MigrationSummary,
}

thread_local! {
    static IN_DATABASE_WORKER: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
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

    fn open_with_capacity_and_registry(
        path: impl AsRef<Path>,
        capacity: usize,
        registry: MigrationRegistry,
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
            }),
            Ok(Err(error)) => {
                let executor = Self {
                    shared,
                    migration_summary: empty_summary(),
                };
                let _ = executor.shutdown();
                Err(error)
            }
            Err(_) => {
                let executor = Self {
                    shared,
                    migration_summary: empty_summary(),
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
        self.submit_job(
            context,
            Box::new(move |connection, operation_context| {
                let transaction = connection
                    .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)
                    .map_err(|error| match operation_error(&error) {
                        SqliteOperationError::Locked => SqliteExecutorError::DatabaseLocked,
                        _ => SqliteExecutorError::Internal,
                    })?;
                let work = SqliteUnitOfWork::new(transaction, operation_context);
                callback(work)
                    .map(|value| Box::new(value) as Box<dyn Any + Send>)
                    .map_err(SqliteExecutorError::ApplicationCallback)
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

        let result = response_receiver.recv().map_err(|_| {
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
                | SqliteExecutorError::DatabaseLocked
                | SqliteExecutorError::Shutdown
                | SqliteExecutorError::Poisoned
                | SqliteExecutorError::Disconnected => {
                    ApplicationPortError::Persistence(PersistenceError::Unavailable)
                }
                SqliteExecutorError::MigrationFailed { .. } => {
                    ApplicationPortError::Persistence(PersistenceError::MigrationFailed)
                }
                SqliteExecutorError::IncompatibleSchema => {
                    ApplicationPortError::Persistence(PersistenceError::CorruptOrIncompatible)
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
