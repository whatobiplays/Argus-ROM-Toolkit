#![cfg(feature = "test-support")]

use argus_application::{
    JobRunId, JobRunState, JobsQueries, OperationContext, OperationDetail, OperationName,
    PersistenceError, SubsystemName, TraceId,
};
use argus_infrastructure::sqlite::{SqliteDatabaseExecutor, SqliteJobsQueries};

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(1).expect("trace"),
        SubsystemName::try_from("test").expect("subsystem"),
        OperationName::try_from("infrastructure").expect("operation"),
    )
}

#[derive(Clone, Copy)]
struct JobFixture {
    id: &'static str,
    state: &'static str,
    issue_count: Option<i64>,
}

fn seed_jobs(executor: &SqliteDatabaseExecutor, fixtures: &[JobFixture]) {
    let mut sql = String::new();
    for fixture in fixtures {
        sql.push_str(&format!(
            "INSERT INTO job_run (job_run_id, operation_type, state, created_at)
             VALUES ('{}', 'library_refresh', '{}', 1);\n",
            fixture.id, fixture.state
        ));
        if let Some(issue_count) = fixture.issue_count {
            sql.push_str(&format!(
                "INSERT INTO library_refresh_issue_summary (job_run_id, issue_count)
                 VALUES ('{}', {});\n",
                fixture.id, issue_count
            ));
            if issue_count > 0 {
                sql.push_str(&format!(
                    "INSERT INTO library_refresh_issue_fact
                         (job_run_id, issue_ordinal, issue_kind, issue_reason, provider_id, occurrences)
                     VALUES ('{}', 0, 'content', 'content_unavailable', NULL, 1);\n",
                    fixture.id
                ));
            }
        }
    }
    executor
        .with_connection_for_tests(context(), move |connection| {
            connection.execute_batch(&sql)?;
            Ok(())
        })
        .expect("seed Library refresh jobs");
}

fn get_refresh_progress(
    executor: &SqliteDatabaseExecutor,
    id: &str,
) -> Result<(JobRunState, Option<u64>, usize), PersistenceError> {
    let detail = SqliteJobsQueries::new(executor.clone())
        .get_job(&context(), JobRunId::try_from(id).expect("job id"))?
        .expect("Library refresh job");
    let state = detail.job().state();
    let OperationDetail::LibraryRefresh(refresh) = detail.operation_detail() else {
        panic!("expected Library refresh detail");
    };
    Ok((
        state,
        refresh.progress().issue_count(),
        refresh.progress().issues().len(),
    ))
}

#[test]
fn non_success_library_refreshes_ignore_stale_issue_summaries() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let fixtures = [
        JobFixture {
            id: "00000000000000000000000000000001",
            state: "queued",
            issue_count: Some(1),
        },
        JobFixture {
            id: "00000000000000000000000000000002",
            state: "preparing",
            issue_count: Some(1),
        },
        JobFixture {
            id: "00000000000000000000000000000003",
            state: "running",
            issue_count: Some(1),
        },
        JobFixture {
            id: "00000000000000000000000000000004",
            state: "running",
            // The stale summary contradicts its one persisted fact.
            issue_count: Some(2),
        },
        JobFixture {
            id: "00000000000000000000000000000005",
            state: "cancelled",
            issue_count: Some(1),
        },
        JobFixture {
            id: "00000000000000000000000000000006",
            state: "failed",
            issue_count: Some(1),
        },
        JobFixture {
            id: "00000000000000000000000000000007",
            state: "interrupted",
            issue_count: Some(1),
        },
        JobFixture {
            id: "00000000000000000000000000000008",
            state: "abandoned",
            issue_count: Some(1),
        },
    ];
    seed_jobs(&executor, &fixtures);

    for fixture in fixtures {
        let (state, issue_count, issue_facts) =
            get_refresh_progress(&executor, fixture.id).expect("GetJob ignores stale summary");
        assert_eq!(state, JobRunState::try_from(fixture.state).expect("state"));
        assert_eq!(
            issue_count, None,
            "state {} is not summary-authoritative",
            fixture.state
        );
        assert_eq!(
            issue_facts, 0,
            "state {} must expose no stale facts",
            fixture.state
        );
    }

    executor.shutdown().expect("shutdown");
}

#[test]
fn successful_library_refreshes_read_summaries_and_preserve_historical_unknowns() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let fixtures = [
        JobFixture {
            id: "00000000000000000000000000000011",
            state: "completed",
            issue_count: Some(0),
        },
        JobFixture {
            id: "00000000000000000000000000000012",
            state: "completed_with_issues",
            issue_count: Some(1),
        },
        JobFixture {
            id: "00000000000000000000000000000013",
            state: "completed",
            issue_count: None,
        },
        JobFixture {
            id: "00000000000000000000000000000014",
            state: "completed_with_issues",
            issue_count: None,
        },
    ];
    seed_jobs(&executor, &fixtures);

    assert_eq!(
        get_refresh_progress(&executor, fixtures[0].id).expect("clean completion"),
        (JobRunState::Completed, Some(0), 0)
    );
    assert_eq!(
        get_refresh_progress(&executor, fixtures[1].id).expect("partial completion"),
        (JobRunState::CompletedWithIssues, Some(1), 1)
    );
    for fixture in &fixtures[2..] {
        let (_, issue_count, issue_facts) =
            get_refresh_progress(&executor, fixture.id).expect("historical detail");
        assert_eq!(issue_count, None);
        assert_eq!(issue_facts, 0);
    }

    executor.shutdown().expect("shutdown");
}

#[test]
fn successful_library_refreshes_reject_summary_fact_mismatches() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let fixtures = [
        JobFixture {
            id: "00000000000000000000000000000021",
            state: "completed",
            issue_count: Some(1),
        },
        JobFixture {
            id: "00000000000000000000000000000022",
            state: "completed_with_issues",
            issue_count: Some(1),
        },
    ];
    seed_jobs(&executor, &fixtures);
    executor
        .with_connection_for_tests(context(), |connection| {
            connection
                .execute_batch("UPDATE library_refresh_issue_summary SET issue_count = 2;")?;
            Ok(())
        })
        .expect("corrupt success summaries");

    for fixture in fixtures {
        assert_eq!(
            get_refresh_progress(&executor, fixture.id).unwrap_err(),
            PersistenceError::CorruptOrIncompatible
        );
    }

    executor.shutdown().expect("shutdown");
}
