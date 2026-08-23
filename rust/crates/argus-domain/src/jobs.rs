//! Stable Phase 001 execution and source-graph identities.
//!
//! `JobRunId` identifies exactly one generic background execution attempt,
//! `ScanRunId` identifies one root-specific scan inside a job, and
//! `SourceEntryId` identifies one persisted source-graph entity. They are
//! provider-independent domain vocabulary and never encode paths, locators,
//! native identities, or fingerprints.

use std::fmt;

macro_rules! hex_identity {
    ($name:ident, $error:ident, $doc:literal) => {
        #[doc = $doc]
        #[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
        pub struct $name([u8; 16]);

        /// Failure while constructing this identity.
        #[derive(Clone, Copy, Debug, Eq, PartialEq)]
        pub struct $error;

        impl fmt::Display for $error {
            fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                formatter.write_str("invalid identity")
            }
        }

        impl std::error::Error for $error {}

        impl $name {
            /// Creates an identity from exactly 16 non-zero bytes.
            pub const fn from_bytes(bytes: [u8; 16]) -> Result<Self, $error> {
                if all_zero(&bytes) {
                    return Err($error);
                }
                Ok(Self(bytes))
            }

            /// Returns the exact 16 identity bytes.
            pub const fn as_bytes(self) -> [u8; 16] {
                self.0
            }
        }

        impl TryFrom<&str> for $name {
            type Error = $error;

            fn try_from(value: &str) -> Result<Self, Self::Error> {
                parse_hex_id(value).map(Self).ok_or($error)
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                write_hex(formatter, self.0)
            }
        }
    };
}

hex_identity!(
    JobRunId,
    JobRunIdError,
    "Stable identity of one background execution attempt."
);
hex_identity!(
    ScanRunId,
    ScanRunIdError,
    "Stable identity of one root-specific scan run."
);
hex_identity!(
    SourceEntryId,
    SourceEntryIdError,
    "Stable identity of one persisted source-graph entity."
);
hex_identity!(
    GameContentId,
    GameContentIdError,
    "Stable identity of one canonical logical content entity."
);
hex_identity!(
    GameId,
    GameIdError,
    "Stable identity of one logical library game entity."
);

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
