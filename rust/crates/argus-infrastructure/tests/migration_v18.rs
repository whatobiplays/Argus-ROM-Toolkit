#![cfg(feature = "test-support")]

use argus_application::{OperationContext, OperationName, SubsystemName, TraceId};
use argus_infrastructure::sqlite::SqliteDatabaseExecutor;
use tempfile::tempdir;

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(1_u128).expect("trace"),
        SubsystemName::try_from("migration").expect("subsystem"),
        OperationName::try_from("v18").expect("operation"),
    )
}

#[test]
fn providerless_refresh_issue_identity_is_unique_after_v18_migration() {
    let directory = tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&database).expect("database");

    let duplicate_rejected = executor
        .with_connection_for_tests(context(), |connection| {
            connection
                .execute_batch(
                    "INSERT INTO job_run (job_run_id, operation_type, state, created_at)
                     VALUES ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'library_refresh', 'completed', 1);
                     INSERT INTO library_refresh_issue_fact
                         (job_run_id, issue_ordinal, issue_kind, issue_reason, provider_id, occurrences)
                     VALUES
                         ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 0, 'content', 'content_unavailable', NULL, 1);",
                )
                .expect("insert first provider-less fact");

            let duplicate = connection.execute_batch(
                "INSERT INTO library_refresh_issue_fact
                     (job_run_id, issue_ordinal, issue_kind, issue_reason, provider_id, occurrences)
                 VALUES
                     ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 1, 'content', 'content_unavailable', NULL, 1);",
            );
            Ok(duplicate.is_err())
        })
        .expect("raw schema regression");
    assert!(
        duplicate_rejected,
        "the complete issue identity must reject a duplicate NULL-provider fact"
    );

    executor.shutdown().expect("shutdown");
}
