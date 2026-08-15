use argus_domain::{
    JobRunId, JobRunIdError, ScanRunId, ScanRunIdError, SourceEntryId, SourceEntryIdError,
};

#[test]
fn job_run_id_rejects_zero_and_invalid_shapes() {
    assert_eq!(JobRunId::from_bytes([0; 16]), Err(JobRunIdError));
    assert_eq!(JobRunId::try_from(""), Err(JobRunIdError));
    assert_eq!(JobRunId::try_from("1234"), Err(JobRunIdError));
    assert_eq!(
        JobRunId::try_from("gggggggggggggggggggggggggggggggg"),
        Err(JobRunIdError)
    );
}

#[test]
fn job_run_id_round_trips_and_displays_lowercase_hex() {
    let bytes = [
        0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef, 0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc,
        0xfe,
    ];
    let id = JobRunId::from_bytes(bytes).expect("non-zero bytes");
    assert_eq!(id.as_bytes(), bytes);
    assert_eq!(id.to_string(), "0123456789abcdef1032547698badcfe");
    assert_eq!(
        JobRunId::try_from("0123456789ABCDEF1032547698BADCfe").expect("case-insensitive"),
        id
    );
}

#[test]
fn scan_run_id_rejects_zero_and_invalid_shapes() {
    assert_eq!(ScanRunId::from_bytes([0; 16]), Err(ScanRunIdError));
    assert_eq!(ScanRunId::try_from(""), Err(ScanRunIdError));
    assert_eq!(ScanRunId::try_from("1234"), Err(ScanRunIdError));
    assert_eq!(
        ScanRunId::try_from("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"),
        Err(ScanRunIdError)
    );
}

#[test]
fn scan_run_id_round_trips_and_displays_lowercase_hex() {
    let bytes = [
        0xfe, 0xdc, 0xba, 0x98, 0x76, 0x54, 0x32, 0x10, 0xef, 0xcd, 0xab, 0x89, 0x67, 0x45, 0x23,
        0x01,
    ];
    let id = ScanRunId::from_bytes(bytes).expect("non-zero bytes");
    assert_eq!(id.as_bytes(), bytes);
    assert_eq!(id.to_string(), "fedcba9876543210efcdab8967452301");
    assert_eq!(
        ScanRunId::try_from("FEDCBA9876543210EFCDAB8967452301").expect("case-insensitive"),
        id
    );
}

#[test]
fn source_entry_id_rejects_zero_and_invalid_shapes() {
    assert_eq!(SourceEntryId::from_bytes([0; 16]), Err(SourceEntryIdError));
    assert_eq!(SourceEntryId::try_from(""), Err(SourceEntryIdError));
    assert_eq!(SourceEntryId::try_from("1234"), Err(SourceEntryIdError));
    assert_eq!(SourceEntryId::try_from("!!!!"), Err(SourceEntryIdError));
}

#[test]
fn source_entry_id_round_trips_and_displays_lowercase_hex() {
    let bytes = [
        0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff,
        0x10,
    ];
    let id = SourceEntryId::from_bytes(bytes).expect("non-zero bytes");
    assert_eq!(id.as_bytes(), bytes);
    assert_eq!(id.to_string(), "112233445566778899aabbccddeeff10");
    assert_eq!(
        SourceEntryId::try_from("112233445566778899AABBCCDDEEFF10").expect("case-insensitive"),
        id
    );
}
