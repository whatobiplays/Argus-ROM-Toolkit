//! Stable Phase 001 source/root identities.
//!
//! These types identify one configured `LibrarySource` instance and one
//! configured `LibraryRoot` scan boundary. They are provider-independent
//! domain vocabulary: provider-boundary contracts such as locators,
//! relationships, and selection input belong to the application boundary.

use std::fmt;

/// Failure while constructing a library-source identity.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct LibrarySourceIdError;

impl fmt::Display for LibrarySourceIdError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("invalid library source identity")
    }
}

impl std::error::Error for LibrarySourceIdError {}

/// Failure while constructing a library-root identity.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct LibraryRootIdError;

impl fmt::Display for LibraryRootIdError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("invalid library root identity")
    }
}

impl std::error::Error for LibraryRootIdError {}

/// Stable identity of one configured local library source.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct LibrarySourceId([u8; 16]);

impl LibrarySourceId {
    /// Creates an identity from exactly 16 non-zero bytes.
    pub const fn from_bytes(bytes: [u8; 16]) -> Result<Self, LibrarySourceIdError> {
        if all_zero(&bytes) {
            return Err(LibrarySourceIdError);
        }
        Ok(Self(bytes))
    }

    /// Returns the exact 16 identity bytes.
    pub const fn as_bytes(self) -> [u8; 16] {
        self.0
    }
}

impl TryFrom<&str> for LibrarySourceId {
    type Error = LibrarySourceIdError;

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        parse_hex_id(value).map(Self).ok_or(LibrarySourceIdError)
    }
}

impl fmt::Display for LibrarySourceId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write_hex(formatter, self.0)
    }
}

/// Stable identity of one configured library root scan boundary.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct LibraryRootId([u8; 16]);

impl LibraryRootId {
    /// Creates an identity from exactly 16 non-zero bytes.
    pub const fn from_bytes(bytes: [u8; 16]) -> Result<Self, LibraryRootIdError> {
        if all_zero(&bytes) {
            return Err(LibraryRootIdError);
        }
        Ok(Self(bytes))
    }

    /// Returns the exact 16 identity bytes.
    pub const fn as_bytes(self) -> [u8; 16] {
        self.0
    }
}

impl TryFrom<&str> for LibraryRootId {
    type Error = LibraryRootIdError;

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        parse_hex_id(value).map(Self).ok_or(LibraryRootIdError)
    }
}

impl fmt::Display for LibraryRootId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write_hex(formatter, self.0)
    }
}

const fn all_zero(bytes: &[u8; 16]) -> bool {
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] != 0 {
            return false;
        }
        index += 1;
    }
    true
}

fn parse_hex_id(value: &str) -> Option<[u8; 16]> {
    if value.len() != 32 {
        return None;
    }
    let mut bytes = [0_u8; 16];
    for (index, pair) in value.as_bytes().chunks_exact(2).enumerate() {
        let high = hex_digit(pair[0])?;
        let low = hex_digit(pair[1])?;
        bytes[index] = (high << 4) | low;
    }
    (!all_zero(&bytes)).then_some(bytes)
}

fn hex_digit(value: u8) -> Option<u8> {
    match value {
        b'0'..=b'9' => Some(value - b'0'),
        b'a'..=b'f' => Some(value - b'a' + 10),
        b'A'..=b'F' => Some(value - b'A' + 10),
        _ => None,
    }
}

fn write_hex(formatter: &mut fmt::Formatter<'_>, bytes: [u8; 16]) -> fmt::Result {
    for byte in bytes {
        write!(formatter, "{byte:02x}")?;
    }
    Ok(())
}
