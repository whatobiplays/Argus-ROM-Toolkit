//! Phase 000 centralized operation admission and shared operation lifecycle.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

use argus_application::{ApplicationError, ErrorCode, TraceId};

/// Static operation classification for Phase 000.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum OperationClass {
    /// Read-oriented operation with no authoritative mutation.
    Query,
    /// Direct immediate command executed inside the initiating operation.
    ImmediateCommand,
}

/// Cooperative cancellation primitive for one admitted bridge operation.
#[derive(Clone, Debug, Default)]
pub struct CancellationToken(Arc<AtomicBool>);

impl CancellationToken {
    /// Creates a token that is initially not cancelled.
    pub fn new() -> Self {
        Self::default()
    }

    /// Requests cooperative cancellation at the next safe boundary.
    pub fn cancel(&self) {
        self.0.store(true, Ordering::SeqCst);
    }

    /// Returns whether cancellation has been requested.
    pub fn is_cancelled(&self) -> bool {
        self.0.load(Ordering::SeqCst)
    }
}

/// Runtime-wide outstanding-operation and shutdown-intent state.
#[derive(Debug)]
pub struct OperationTracker {
    outstanding: usize,
    cancellation_requested: bool,
    tokens: Vec<CancellationToken>,
    condvar: Arc<Condvar>,
}

impl Default for OperationTracker {
    fn default() -> Self {
        Self::new()
    }
}

impl OperationTracker {
    /// Creates an open tracker with no outstanding operations.
    pub fn new() -> Self {
        Self {
            outstanding: 0,
            cancellation_requested: false,
            tokens: Vec::new(),
            condvar: Arc::new(Condvar::new()),
        }
    }

    /// Whether shutdown/pre-dispatch cancellation has been requested.
    pub fn is_cancellation_requested(&self) -> bool {
        self.cancellation_requested
    }

    /// Closes admission and signals every outstanding token.
    pub fn request_cancellation(&mut self) {
        self.cancellation_requested = true;
        for token in &self.tokens {
            token.cancel();
        }
    }

    /// Admits one operation when admission is open.
    pub fn admit(&mut self) -> Option<CancellationToken> {
        if self.cancellation_requested {
            return None;
        }
        let token = CancellationToken::new();
        self.outstanding += 1;
        self.tokens.push(token.clone());
        Some(token)
    }

    /// Completes one admitted operation.
    pub fn finish(&mut self, token: &CancellationToken) {
        self.tokens
            .retain(|candidate| !Arc::ptr_eq(&candidate.0, &token.0));
        self.outstanding = self.outstanding.saturating_sub(1);
        self.condvar.notify_all();
    }

    /// Returns the number of outstanding admitted operations.
    pub fn outstanding(&self) -> usize {
        self.outstanding
    }

    /// Returns outstanding operations excluding one self-owned token.
    pub fn outstanding_excluding(&self, excluded: Option<&CancellationToken>) -> usize {
        self.tokens
            .iter()
            .filter(|token| !excluded.is_some_and(|excluded| Arc::ptr_eq(&token.0, &excluded.0)))
            .count()
    }
}

/// Waits up to `timeout` for all admitted operations tracked by `tracker`.
pub fn wait_until_empty(tracker: &Mutex<OperationTracker>, timeout: Duration) -> bool {
    wait_until_empty_excluding(tracker, Instant::now() + timeout, None)
}

/// Waits until `deadline` for all admitted operations to finish.
pub fn wait_until_empty_until(tracker: &Mutex<OperationTracker>, deadline: Instant) -> bool {
    wait_until_empty_excluding(tracker, deadline, None)
}

/// Waits until `deadline`, excluding one self-owned operation token.
pub fn wait_until_empty_excluding(
    tracker: &Mutex<OperationTracker>,
    deadline: Instant,
    excluded: Option<&CancellationToken>,
) -> bool {
    let mut guard = tracker.lock().expect("operation tracker lock");
    let condvar = guard.condvar.clone();
    while guard.outstanding_excluding(excluded) > 0 {
        let now = Instant::now();
        if now >= deadline {
            return false;
        }
        let (next, wait_result) = condvar
            .wait_timeout(guard, deadline.saturating_duration_since(now))
            .expect("operation tracker wait");
        guard = next;
        if wait_result.timed_out() {
            return guard.outstanding_excluding(excluded) == 0;
        }
    }
    true
}

/// RAII ownership of one admitted operation.
pub struct OperationGuard {
    token: CancellationToken,
    tracker: Arc<Mutex<OperationTracker>>,
}

impl OperationGuard {
    /// Creates an operation guard for the supplied admitted token.
    pub fn new(token: CancellationToken, tracker: Arc<Mutex<OperationTracker>>) -> Self {
        Self { token, tracker }
    }

    /// Returns the cooperative cancellation token.
    pub fn token(&self) -> &CancellationToken {
        &self.token
    }

    /// Completes the operation immediately.
    pub fn finish(self) {
        drop(self);
    }
}

impl Drop for OperationGuard {
    fn drop(&mut self) {
        if let Ok(mut tracker) = self.tracker.lock() {
            tracker.finish(&self.token);
        }
    }
}

/// Builds the published pre-admission cancellation failure.
pub fn cancelled_error() -> ApplicationError {
    cancelled_error_with_trace(crate::new_trace_id())
}

/// Builds the published pre-admission cancellation failure with a trace.
pub fn cancelled_error_with_trace(trace_id: TraceId) -> ApplicationError {
    ApplicationError::from_code(
        ErrorCode::OperationCancelled,
        trace_id,
        argus_application::SafeContext::new(),
    )
    .expect("operation cancelled uses an allowlisted empty context")
}

#[cfg(test)]
mod tests {
    use super::{OperationGuard, OperationTracker, wait_until_empty};
    use std::sync::{Arc, Mutex};
    use std::time::Duration;

    #[test]
    fn admission_rejects_after_cancellation_is_requested() {
        let mut tracker = OperationTracker::new();
        let token = tracker.admit().expect("first admission");
        tracker.request_cancellation();
        assert!(tracker.admit().is_none());
        assert!(token.is_cancelled());
    }

    #[test]
    fn finish_tracks_outstanding_and_signals_waiters() {
        let tracker = Arc::new(Mutex::new(OperationTracker::new()));
        let token = tracker.lock().expect("tracker").admit().expect("admission");
        assert_eq!(tracker.lock().expect("tracker").outstanding(), 1);
        let wait_tracker = Arc::clone(&tracker);
        let waiter =
            std::thread::spawn(move || wait_until_empty(&wait_tracker, Duration::from_secs(5)));
        drop(OperationGuard::new(token, Arc::clone(&tracker)));
        assert!(waiter.join().expect("waiter"));
        assert_eq!(tracker.lock().expect("tracker").outstanding(), 0);
    }
}
