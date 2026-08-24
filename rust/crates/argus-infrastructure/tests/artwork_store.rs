use argus_domain::ArtworkAssetId;
use argus_infrastructure::artwork_store::{ArtworkObjectStore, ArtworkObjectStoreError};
use image::ImageEncoder;

fn one_by_one_png() -> Vec<u8> {
    let mut bytes = Vec::new();
    image::codecs::png::PngEncoder::new(&mut bytes)
        .write_image(&[255, 0, 0, 255], 1, 1, image::ExtendedColorType::Rgba8)
        .expect("encode fixture");
    bytes
}

#[test]
fn artwork_bytes_are_content_addressed_and_deduplicated() {
    let directory = tempfile::tempdir().expect("temporary artwork directory");
    let store = ArtworkObjectStore::new(directory.path()).expect("object store");
    let bytes = one_by_one_png();

    let first = store.store(&bytes).expect("first write");
    let second = store.store(&bytes).expect("deduplicated write");

    assert_eq!(first.asset_id(), second.asset_id());
    assert_eq!(first.width(), 1);
    assert_eq!(first.height(), 1);
    assert_eq!(first.mime_type(), "image/png");
    assert_eq!(first.byte_size(), bytes.len() as u64);
    assert_eq!(store.read(first.asset_id()).expect("read asset"), bytes);
    let key = first.asset_id().to_string();
    assert!(
        directory
            .path()
            .join("artwork-assets")
            .join(&key[..2])
            .join(&key[2..4])
            .join(key)
            .is_file()
    );
}

#[test]
fn artwork_store_rejects_malformed_and_oversized_input() {
    let directory = tempfile::tempdir().expect("temporary artwork directory");
    let store = ArtworkObjectStore::with_limits(directory.path(), 16, 4096).expect("object store");

    assert!(matches!(
        store.store(b"not an image"),
        Err(ArtworkObjectStoreError::InvalidImage)
    ));
    assert!(matches!(
        store.store(&[0_u8; 17]),
        Err(ArtworkObjectStoreError::TooLarge)
    ));
}

#[test]
fn artwork_store_rejects_missing_or_corrupt_content_addressed_files() {
    let directory = tempfile::tempdir().expect("temporary artwork directory");
    let store = ArtworkObjectStore::new(directory.path()).expect("object store");
    let asset = store.store(&one_by_one_png()).expect("write asset");
    let key = asset.asset_id().to_string();
    let path = directory
        .path()
        .join("artwork-assets")
        .join(&key[..2])
        .join(&key[2..4])
        .join(key);
    std::fs::write(path, b"changed").expect("corrupt asset");

    assert!(matches!(
        store.read(asset.asset_id()),
        Err(ArtworkObjectStoreError::Corrupt)
    ));
    let unknown = ArtworkAssetId::from_bytes([1_u8; 32]).expect("non-zero id");
    assert!(matches!(
        store.read(unknown),
        Err(ArtworkObjectStoreError::NotFound)
    ));
}
