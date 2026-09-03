#![cfg(unix)]

mod common;

use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::thread;
use std::time::{Duration, Instant};

use argus_application::{LibrarySourceAccess, RelativeSourceLocator};

const CHILD_ENV: &str = "ARGUS_FIFO_REVALIDATION_CHILD";
const PATH_ENV: &str = "ARGUS_FIFO_REVALIDATION_PATH";

#[test]
fn fifo_revalidation_returns_changed_without_blocking() {
    if std::env::var_os(CHILD_ENV).is_some() {
        run_fifo_revalidation_case();
        return;
    }

    let directory = tempfile::tempdir().expect("tempdir");
    let path = directory.path().join("source.bin");
    let test_binary = std::env::current_exe().expect("test binary");
    let mut child = Command::new(test_binary)
        .arg("--exact")
        .arg("fifo_revalidation_returns_changed_without_blocking")
        .arg("--nocapture")
        .env(CHILD_ENV, "1")
        .env(PATH_ENV, path.as_os_str())
        .spawn()
        .expect("spawn isolated FIFO regression");

    let deadline = Instant::now() + Duration::from_secs(2);
    loop {
        if let Some(status) = child.try_wait().expect("poll child") {
            assert!(
                status.success(),
                "isolated FIFO regression failed: {status}"
            );
            return;
        }
        if Instant::now() >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            panic!("source revalidation blocked while opening a FIFO");
        }
        thread::sleep(Duration::from_millis(10));
    }
}

fn run_fifo_revalidation_case() {
    let path = PathBuf::from(std::env::var_os(PATH_ENV).expect("FIFO path"));
    let root = path.parent().expect("FIFO root");
    fs::write(&path, b"source").expect("source file");

    let access = common::access(root);
    let resolved = access.resolve_root().expect("resolve root");
    let reader = access
        .open_entry_reader(
            &resolved,
            &RelativeSourceLocator::from_provider("source.bin".to_owned()),
        )
        .expect("open source");

    fs::remove_file(&path).expect("remove source file");
    let status = Command::new("mkfifo")
        .arg(&path)
        .status()
        .expect("create FIFO");
    assert!(status.success(), "mkfifo failed: {status}");

    assert_eq!(reader.source_version_is_unchanged(), Ok(false));
}
