//! Content-addressed artwork byte storage.
//!
//! The object store validates image structure and dimensions before writing
//! bytes below the application-private data directory. It never transforms
//! or resizes artwork. The persisted key is derived only from the BLAKE3
//! digest, so the store cannot be used to address arbitrary filesystem paths.

use std::fs::{self, File, OpenOptions};
use std::io::{Cursor, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use argus_application::{ArtworkAsset, ArtworkAssetStore, ArtworkAssetStoreError};
use argus_domain::{ArtworkAssetId, ArtworkAssetIdError};
use image::{ImageFormat, ImageReader};

/// Default encoded artwork limit: 20 MiB.
pub const DEFAULT_MAX_BYTES: u64 = 20 * 1024 * 1024;
/// Default maximum width or height accepted by the decoder.
pub const DEFAULT_MAX_DIMENSION: u32 = 16_384;

static TEMP_FILE_COUNTER: AtomicU64 = AtomicU64::new(0);

/// Safe failure vocabulary for artwork object-store operations.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ArtworkObjectStoreError {
    /// The encoded bytes are larger than the configured bound.
    TooLarge,
    /// The bytes are not a supported, structurally valid image.
    InvalidImage,
    /// The image dimensions exceed the configured bound.
    DimensionsTooLarge,
    /// The requested content-addressed object does not exist.
    NotFound,
    /// A stored object no longer matches its content address.
    Corrupt,
    /// The configured storage root or an I/O operation failed.
    Io,
    /// The object-store bounds are invalid.
    InvalidConfiguration,
}

/// Application-private, content-addressed artwork object store.
#[derive(Clone, Debug)]
pub struct ArtworkObjectStore {
    root: PathBuf,
    max_bytes: u64,
    max_dimension: u32,
}

impl ArtworkObjectStore {
    /// Creates a store using the production safety limits.
    pub fn new(root: impl AsRef<Path>) -> Result<Self, ArtworkObjectStoreError> {
        Self::with_limits(root, DEFAULT_MAX_BYTES, DEFAULT_MAX_DIMENSION)
    }

    /// Creates a store with explicit limits for tests and controlled hosts.
    pub fn with_limits(
        root: impl AsRef<Path>,
        max_bytes: u64,
        max_dimension: u32,
    ) -> Result<Self, ArtworkObjectStoreError> {
        if max_bytes == 0 || max_dimension == 0 {
            return Err(ArtworkObjectStoreError::InvalidConfiguration);
        }
        let root = root.as_ref().to_path_buf();
        fs::create_dir_all(&root).map_err(|_| ArtworkObjectStoreError::Io)?;
        Ok(Self {
            root,
            max_bytes,
            max_dimension,
        })
    }

    /// Validates and atomically stores bytes, returning their safe metadata.
    pub fn store(&self, bytes: &[u8]) -> Result<ArtworkAsset, ArtworkObjectStoreError> {
        let byte_size =
            u64::try_from(bytes.len()).map_err(|_| ArtworkObjectStoreError::TooLarge)?;
        if byte_size > self.max_bytes {
            return Err(ArtworkObjectStoreError::TooLarge);
        }
        let (format, width, height) = self.inspect(bytes)?;
        let digest = blake3::hash(bytes);
        let asset_id = ArtworkAssetId::from_bytes(*digest.as_bytes())
            .map_err(|_: ArtworkAssetIdError| ArtworkObjectStoreError::Corrupt)?;
        let storage_key = storage_key(asset_id);
        let destination = self.root.join(&storage_key);
        if destination.exists() {
            self.verify_existing(&destination, asset_id)?;
        } else {
            self.write_once(&destination, bytes)?;
            self.verify_existing(&destination, asset_id)?;
        }
        Ok(ArtworkAsset::new(
            asset_id,
            width,
            height,
            mime_type(format),
            byte_size,
        ))
    }

    /// Reads one immutable asset after verifying its content address.
    pub fn read(&self, asset_id: ArtworkAssetId) -> Result<Vec<u8>, ArtworkObjectStoreError> {
        let path = self.root.join(storage_key(asset_id));
        let metadata = fs::metadata(&path).map_err(|error| {
            if error.kind() == std::io::ErrorKind::NotFound {
                ArtworkObjectStoreError::NotFound
            } else {
                ArtworkObjectStoreError::Io
            }
        })?;
        if metadata.len() > self.max_bytes {
            return Err(ArtworkObjectStoreError::TooLarge);
        }
        let bytes = read_bounded_file(&path, self.max_bytes)?;
        if blake3::hash(&bytes).as_bytes() != &asset_id.as_bytes() {
            return Err(ArtworkObjectStoreError::Corrupt);
        }
        Ok(bytes)
    }

    /// Reads one asset and reconstructs its safe media metadata from the
    /// immutable original bytes.
    pub fn read_asset(
        &self,
        asset_id: ArtworkAssetId,
    ) -> Result<(ArtworkAsset, Vec<u8>), ArtworkObjectStoreError> {
        let bytes = self.read(asset_id)?;
        let (format, width, height) = self.inspect(&bytes)?;
        let byte_size =
            u64::try_from(bytes.len()).map_err(|_| ArtworkObjectStoreError::TooLarge)?;
        Ok((
            ArtworkAsset::new(asset_id, width, height, mime_type(format), byte_size),
            bytes,
        ))
    }

    fn inspect(&self, bytes: &[u8]) -> Result<(ImageFormat, u32, u32), ArtworkObjectStoreError> {
        let reader = ImageReader::new(Cursor::new(bytes))
            .with_guessed_format()
            .map_err(|_| ArtworkObjectStoreError::InvalidImage)?;
        let format = reader
            .format()
            .ok_or(ArtworkObjectStoreError::InvalidImage)?;
        let (width, height) = reader
            .into_dimensions()
            .map_err(|_| ArtworkObjectStoreError::InvalidImage)?;
        if width > self.max_dimension || height > self.max_dimension {
            return Err(ArtworkObjectStoreError::DimensionsTooLarge);
        }
        image::load_from_memory_with_format(bytes, format)
            .map_err(|_| ArtworkObjectStoreError::InvalidImage)?;
        Ok((format, width, height))
    }

    fn verify_existing(
        &self,
        path: &Path,
        asset_id: ArtworkAssetId,
    ) -> Result<(), ArtworkObjectStoreError> {
        let metadata = fs::metadata(path).map_err(|_| ArtworkObjectStoreError::Io)?;
        if metadata.len() > self.max_bytes {
            return Err(ArtworkObjectStoreError::TooLarge);
        }
        let existing = read_bounded_file(path, self.max_bytes)?;
        if blake3::hash(&existing).as_bytes() != &asset_id.as_bytes() {
            return Err(ArtworkObjectStoreError::Corrupt);
        }
        Ok(())
    }

    fn write_once(&self, destination: &Path, bytes: &[u8]) -> Result<(), ArtworkObjectStoreError> {
        let parent = destination.parent().ok_or(ArtworkObjectStoreError::Io)?;
        fs::create_dir_all(parent).map_err(|_| ArtworkObjectStoreError::Io)?;
        let mut temporary = None;
        for _ in 0..128_u8 {
            let sequence = TEMP_FILE_COUNTER.fetch_add(1, Ordering::Relaxed);
            let candidate = parent.join(format!(
                ".{}.tmp-{}-{}",
                destination
                    .file_name()
                    .and_then(|name| name.to_str())
                    .ok_or(ArtworkObjectStoreError::Io)?,
                std::process::id(),
                sequence
            ));
            match OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&candidate)
            {
                Ok(file) => {
                    temporary = Some((candidate, file));
                    break;
                }
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(_) => return Err(ArtworkObjectStoreError::Io),
            }
        }
        let Some((temporary_path, mut file)) = temporary else {
            return Err(ArtworkObjectStoreError::Io);
        };
        if let Err(error) = write_and_sync(&mut file, bytes) {
            let _ = fs::remove_file(&temporary_path);
            return Err(error);
        }
        match fs::rename(&temporary_path, destination) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
                let _ = fs::remove_file(&temporary_path);
                Ok(())
            }
            Err(_) => {
                let _ = fs::remove_file(&temporary_path);
                Err(ArtworkObjectStoreError::Io)
            }
        }
    }
}

impl ArtworkAssetStore for ArtworkObjectStore {
    fn store(&self, bytes: &[u8]) -> Result<ArtworkAsset, ArtworkAssetStoreError> {
        ArtworkObjectStore::store(self, bytes).map_err(|error| match error {
            ArtworkObjectStoreError::TooLarge => ArtworkAssetStoreError::TooLarge,
            ArtworkObjectStoreError::InvalidImage => ArtworkAssetStoreError::InvalidImage,
            ArtworkObjectStoreError::DimensionsTooLarge => {
                ArtworkAssetStoreError::DimensionsTooLarge
            }
            ArtworkObjectStoreError::NotFound
            | ArtworkObjectStoreError::Corrupt
            | ArtworkObjectStoreError::Io
            | ArtworkObjectStoreError::InvalidConfiguration => ArtworkAssetStoreError::Unavailable,
        })
    }
}

fn write_and_sync(file: &mut File, bytes: &[u8]) -> Result<(), ArtworkObjectStoreError> {
    file.write_all(bytes)
        .map_err(|_| ArtworkObjectStoreError::Io)?;
    file.sync_all().map_err(|_| ArtworkObjectStoreError::Io)
}

fn read_bounded_file(path: &Path, max_bytes: u64) -> Result<Vec<u8>, ArtworkObjectStoreError> {
    let file = File::open(path).map_err(|_| ArtworkObjectStoreError::Io)?;
    let read_limit = max_bytes
        .checked_add(1)
        .ok_or(ArtworkObjectStoreError::TooLarge)?;
    let capacity = usize::try_from(read_limit).unwrap_or(usize::MAX);
    let mut bytes = Vec::with_capacity(capacity.min(64 * 1024));
    file.take(read_limit)
        .read_to_end(&mut bytes)
        .map_err(|_| ArtworkObjectStoreError::Io)?;
    if u64::try_from(bytes.len()).unwrap_or(u64::MAX) > max_bytes {
        return Err(ArtworkObjectStoreError::TooLarge);
    }
    Ok(bytes)
}

fn storage_key(asset_id: ArtworkAssetId) -> String {
    let text = asset_id.to_string();
    format!("artwork-assets/{}/{}/{}", &text[..2], &text[2..4], text)
}

fn mime_type(format: ImageFormat) -> &'static str {
    match format {
        ImageFormat::Bmp => "image/bmp",
        ImageFormat::Gif => "image/gif",
        ImageFormat::Jpeg => "image/jpeg",
        ImageFormat::Png => "image/png",
        ImageFormat::WebP => "image/webp",
        _ => "application/octet-stream",
    }
}
