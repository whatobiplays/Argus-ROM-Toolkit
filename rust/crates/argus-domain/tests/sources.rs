//! Contract tests for the stable Phase 001 source/root identities.

use argus_domain::{LibraryRootId, LibraryRootIdError, LibrarySourceId, LibrarySourceIdError};

const ROOT_HEX: &str = "0123456789abcdef0123456789abcdef";
const SOURCE_HEX: &str = "fedcba9876543210fedcba9876543210";
const ZERO_HEX: &str = "00000000000000000000000000000000";

#[test]
fn root_id_parses_canonical_lowercase_hex() {
    let id = LibraryRootId::try_from(ROOT_HEX).expect("valid root id");

    assert_eq!(id.to_string(), ROOT_HEX);
    assert_eq!(id.as_bytes(), hex_bytes(ROOT_HEX));
}

#[test]
fn root_id_rejects_malformed_text() {
    for value in [
        "",
        "abc",
        "0123456789abcdef0123456789abcdeZ",
        "0123456789abcdef0123456789abcdef0",
        ZERO_HEX,
    ] {
        assert_eq!(LibraryRootId::try_from(value), Err(LibraryRootIdError));
    }
}

#[test]
fn root_id_accepts_uppercase_hex_and_displays_canonical_lowercase() {
    let id = LibraryRootId::try_from("0123456789ABCDEF0123456789ABCDEF").expect("uppercase id");

    assert_eq!(id.to_string(), ROOT_HEX);
    assert_eq!(id.as_bytes(), hex_bytes(ROOT_HEX));
}

#[test]
fn root_id_round_trips_through_bytes() {
    let bytes = hex_bytes(ROOT_HEX);

    let id = LibraryRootId::from_bytes(bytes).expect("valid bytes");

    assert_eq!(id.as_bytes(), bytes);
    assert_eq!(id.to_string(), ROOT_HEX);
    assert_eq!(LibraryRootId::from_bytes([0; 16]), Err(LibraryRootIdError));
}

#[test]
fn source_id_parses_canonical_lowercase_hex() {
    let id = LibrarySourceId::try_from(SOURCE_HEX).expect("valid source id");

    assert_eq!(id.to_string(), SOURCE_HEX);
    assert_eq!(id.as_bytes(), hex_bytes(SOURCE_HEX));
}

#[test]
fn source_id_rejects_malformed_text() {
    for value in ["", "xyz", ZERO_HEX] {
        assert_eq!(LibrarySourceId::try_from(value), Err(LibrarySourceIdError));
    }
}

#[test]
fn source_id_accepts_uppercase_hex_and_displays_canonical_lowercase() {
    let id = LibrarySourceId::try_from("FEDCBA9876543210FEDCBA9876543210").expect("uppercase id");

    assert_eq!(id.to_string(), SOURCE_HEX);
    assert_eq!(id.as_bytes(), hex_bytes(SOURCE_HEX));
}

#[test]
fn source_id_round_trips_through_bytes() {
    let bytes = hex_bytes(SOURCE_HEX);

    let id = LibrarySourceId::from_bytes(bytes).expect("valid bytes");

    assert_eq!(id.as_bytes(), bytes);
    assert_eq!(id.to_string(), SOURCE_HEX);
    assert_eq!(
        LibrarySourceId::from_bytes([0; 16]),
        Err(LibrarySourceIdError)
    );
}

#[test]
fn source_and_root_identities_are_independent_types() {
    // These assertions only compile when the two identity types are distinct
    // and expose the same bounded vocabulary.
    let root = LibraryRootId::try_from(ROOT_HEX).expect("root id");
    let source = LibrarySourceId::try_from(SOURCE_HEX).expect("source id");

    assert_ne!(root.to_string(), source.to_string());
    assert_ne!(root.as_bytes(), source.as_bytes());
}

fn hex_bytes(value: &str) -> [u8; 16] {
    let mut bytes = [0_u8; 16];
    for (index, pair) in value.as_bytes().chunks_exact(2).enumerate() {
        let high = hex_digit(pair[0]);
        let low = hex_digit(pair[1]);
        bytes[index] = (high << 4) | low;
    }
    bytes
}

fn hex_digit(value: u8) -> u8 {
    match value {
        b'0'..=b'9' => value - b'0',
        b'a'..=b'f' => value - b'a' + 10,
        _ => panic!("fixture contains non-hex byte"),
    }
}
