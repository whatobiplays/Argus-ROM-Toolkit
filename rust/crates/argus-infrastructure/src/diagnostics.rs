//! Concrete diagnostic ZIP writing and path sanitization owned by
//! infrastructure.

use std::fs::File;
use std::io::{self, Write};
use std::path::Path;

/// Writes a version-1 diagnostic ZIP archive.
pub struct DiagnosticZipWriter {
    inner: zip::ZipWriter<File>,
}

impl DiagnosticZipWriter {
    /// Creates the archive at the user-selected destination.
    pub fn create(destination: &Path) -> io::Result<Self> {
        Ok(Self {
            inner: zip::ZipWriter::new(File::create(destination)?),
        })
    }

    /// Adds one already-sanitized artifact.
    pub fn add_artifact(&mut self, name: &str, contents: &[u8]) -> io::Result<()> {
        let options = zip::write::SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Deflated);
        self.inner.start_file(name, options)?;
        self.inner.write_all(contents)?;
        Ok(())
    }

    /// Finalizes the archive.
    pub fn finish(self) -> io::Result<()> {
        self.inner.finish()?;
        Ok(())
    }
}

/// Returns a stable logical classification for a data-directory path.
pub fn path_classification(path: &Path) -> String {
    let name = path
        .file_name()
        .map(|name| name.to_string_lossy().to_string())
        .unwrap_or_default();
    if name.to_ascii_lowercase().contains("argus") {
        "standard_application_data".to_owned()
    } else {
        "user_selected".to_owned()
    }
}

/// Opens a data directory with the host desktop shell.
pub fn open_data_directory(path: &Path) -> io::Result<()> {
    #[cfg(target_os = "macos")]
    let command = "open";
    #[cfg(target_os = "windows")]
    let command = "explorer";
    #[cfg(all(unix, not(target_os = "macos")))]
    let command = "xdg-open";
    std::process::Command::new(command)
        .arg(path)
        .spawn()
        .map(|_| ())
}
