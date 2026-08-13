//! Bridge-neutral outward runtime notification sink port.

use std::sync::{Arc, Mutex};

use crate::{EventBoundary, RuntimeEventPayload, RuntimeInstanceId};

/// Failure while delivering one outward notification.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NotificationSinkError {
    Unavailable,
}

/// Outward notification sink supplied by the embedding bridge adapter.
pub trait RuntimeNotificationSink: Send + Sync {
    /// Binds this adapter to the authoritative outward publisher.
    fn bind(&self, publisher: Arc<RuntimeEventPublisher>) -> Result<(), NotificationSinkError>;

    /// Validates adapter registration without emitting a user-visible event.
    fn validate(&self) -> Result<(), NotificationSinkError>;

    /// Publishes one notification-first runtime payload through the bound
    /// publisher; the publisher owns envelope and sequence allocation.
    fn publish(&self, event: RuntimeEventPayload) -> Result<(), NotificationSinkError>;
}

/// Bridge-neutral runtime publisher handle owned by the runtime. The bridge
/// adapter binds to this handle and emits through it, so there is exactly one
/// outward publication route.
pub struct RuntimeEventPublisher {
    generation: RuntimeInstanceId,
    boundary: Arc<EventBoundary>,
}

impl RuntimeEventPublisher {
    /// Creates a publisher bound to one generation's boundary.
    pub(crate) fn new(generation: RuntimeInstanceId, boundary: Arc<EventBoundary>) -> Arc<Self> {
        Arc::new(Self {
            generation,
            boundary,
        })
    }

    /// Emits one notification-first payload, allocating the runtime sequence.
    pub fn emit(&self, payload: RuntimeEventPayload) -> Result<(), NotificationSinkError> {
        self.boundary.emit(self.generation, payload);
        Ok(())
    }

    /// Returns whether the underlying boundary is still open.
    pub fn is_open(&self) -> bool {
        self.boundary.is_open()
    }
}

/// Bounded in-process sink used by non-bridge embeddings and tests.
pub struct InProcessNotificationSink {
    buffer: Mutex<Vec<RuntimeEventPayload>>,
    publisher: Mutex<Option<Arc<RuntimeEventPublisher>>>,
}

impl InProcessNotificationSink {
    /// Creates an empty bounded sink.
    pub fn new() -> Self {
        Self {
            buffer: Mutex::new(Vec::new()),
            publisher: Mutex::new(None),
        }
    }

    /// Returns the number of buffered notifications.
    pub fn len(&self) -> usize {
        self.buffer.lock().map(|buffer| buffer.len()).unwrap_or(0)
    }

    /// Returns whether no notifications are buffered.
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

impl Default for InProcessNotificationSink {
    fn default() -> Self {
        Self::new()
    }
}

impl RuntimeNotificationSink for InProcessNotificationSink {
    fn bind(&self, publisher: Arc<RuntimeEventPublisher>) -> Result<(), NotificationSinkError> {
        *self
            .publisher
            .lock()
            .map_err(|_| NotificationSinkError::Unavailable)? = Some(publisher);
        Ok(())
    }

    fn validate(&self) -> Result<(), NotificationSinkError> {
        let publisher = self
            .publisher
            .lock()
            .map_err(|_| NotificationSinkError::Unavailable)?;
        match publisher.as_ref() {
            Some(publisher) if publisher.is_open() => Ok(()),
            _ => Err(NotificationSinkError::Unavailable),
        }
    }

    fn publish(&self, event: RuntimeEventPayload) -> Result<(), NotificationSinkError> {
        let publisher = self
            .publisher
            .lock()
            .map_err(|_| NotificationSinkError::Unavailable)?;
        let publisher = publisher
            .as_ref()
            .ok_or(NotificationSinkError::Unavailable)?;
        publisher.emit(event.clone())?;
        if let Ok(mut buffer) = self.buffer.lock()
            && buffer.len() < 64
        {
            buffer.push(event);
        }
        Ok(())
    }
}
