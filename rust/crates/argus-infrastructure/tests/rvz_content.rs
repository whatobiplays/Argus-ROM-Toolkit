use aes::Aes128;
use aes::cipher::{BlockEncrypt, KeyInit};
use argus_application::{ContentType, PlatformId, TransformationBudget};
use argus_infrastructure::content::{
    ContentReadError, ContentReader, OpticalError, ParsingSession, recognize_native_optical,
    recognize_rvz,
};
use ruzstd::encoding::{CompressionLevel, compress_to_vec};
use sha1::{Digest, Sha1};
use tempfile::tempdir;

const CHUNK_BYTES: usize = 0x8000;

struct MemoryReader {
    bytes: Vec<u8>,
}

impl MemoryReader {
    fn new(bytes: Vec<u8>) -> Self {
        Self { bytes }
    }
}

impl ContentReader for MemoryReader {
    fn len(&self) -> Result<u64, ContentReadError> {
        Ok(self.bytes.len() as u64)
    }

    fn read_at(&mut self, offset: u64, destination: &mut [u8]) -> Result<usize, ContentReadError> {
        let start = usize::try_from(offset).map_err(|_| ContentReadError::OutOfRange)?;
        let end = start
            .checked_add(destination.len())
            .ok_or(ContentReadError::OutOfRange)?;
        let source = self
            .bytes
            .get(start..end)
            .ok_or(ContentReadError::OutOfRange)?;
        destination.copy_from_slice(source);
        Ok(source.len())
    }
}

fn budget(max_work: u64, max_expanded: u64) -> TransformationBudget {
    TransformationBudget::new(
        128 * 1024 * 1024,
        max_expanded,
        65_536,
        4,
        128 * 1024 * 1024,
        max_work,
    )
}

fn recognize(
    bytes: Vec<u8>,
    max_work: u64,
    max_expanded: u64,
) -> Result<argus_infrastructure::content::OpticalRecognition, OpticalError> {
    let staging = tempdir().expect("staging");
    let mut session =
        ParsingSession::for_tests(budget(max_work, max_expanded), staging.path(), || false);
    let mut reader = MemoryReader::new(bytes);
    recognize_rvz(&mut reader, &mut session)
}

fn set_u32_be(bytes: &mut [u8], offset: usize, value: u32) {
    bytes[offset..offset + 4].copy_from_slice(&value.to_be_bytes());
}

fn set_u64_be(bytes: &mut [u8], offset: usize, value: u64) {
    bytes[offset..offset + 8].copy_from_slice(&value.to_be_bytes());
}

fn build_valid_gamecube_image() -> Vec<u8> {
    let mut image = vec![0_u8; CHUNK_BYTES];
    image[..6].copy_from_slice(b"GM8E01");
    image[0x1c..0x20].copy_from_slice(&[0xc2, 0x33, 0x9f, 0x3d]);
    set_u32_be(&mut image, 0x420, 0x2800);
    set_u32_be(&mut image, 0x424, 0x3000);
    set_u32_be(&mut image, 0x428, 33);
    set_u32_be(&mut image, 0x42c, 33);
    set_u32_be(&mut image, 0x2440 + 0x14, 0x20);
    set_u32_be(&mut image, 0x2440 + 0x18, 0);
    set_u32_be(&mut image, 0x2800, 0x2800);
    set_u32_be(&mut image, 0x2800 + 0x90, 0x20);
    let fst = 0x3000;
    image[fst] = 1;
    set_u32_be(&mut image, fst + 8, 2);
    set_u32_be(&mut image, fst + 12 + 4, 0x2800);
    set_u32_be(&mut image, fst + 12 + 8, 0x20);
    image[fst + 24..fst + 33].copy_from_slice(b"main.dol\0");
    image
}

fn build_valid_wii_image() -> Vec<u8> {
    let mut image = vec![0_u8; CHUNK_BYTES * 16];
    image[..6].copy_from_slice(b"RMCP01");
    image[0x18..0x1c].copy_from_slice(&[0x5d, 0x1c, 0x9e, 0xa3]);
    set_u32_be(&mut image, 0x4fffc, 0xc3f8_1a8e);
    set_u32_be(&mut image, 0x40000, 1);
    set_u32_be(&mut image, 0x40004, 0x100);
    set_u32_be(&mut image, 0x40400, 0x50000 >> 2);
    set_u32_be(&mut image, 0x40404, 0);
    set_u32_be(&mut image, 0x50000 + 0x2b8, 0x4000 >> 2);
    set_u32_be(&mut image, 0x50000 + 0x2bc, 0x20000 >> 2);
    image
}

fn cbc_encrypt(cipher: &Aes128, input: &[u8], output: &mut [u8], initial_vector: [u8; 16]) {
    assert_eq!(input.len(), output.len());
    assert!(input.len().is_multiple_of(16));
    let mut previous = initial_vector;
    for (source, destination) in input.chunks_exact(16).zip(output.chunks_exact_mut(16)) {
        let mut block = aes::cipher::Block::<Aes128>::default();
        for index in 0..16 {
            block[index] = source[index] ^ previous[index];
        }
        cipher.encrypt_block(&mut block);
        destination.copy_from_slice(&block);
        previous.copy_from_slice(&block);
    }
}

fn encrypted_wii_partition_group(decrypted: &[u8], key: [u8; 16]) -> Vec<u8> {
    const BLOCK_DATA_BYTES: usize = 0x7c00;
    const BLOCK_HEADER_BYTES: usize = 0x400;
    const BLOCK_TOTAL_BYTES: usize = 0x8000;
    const BLOCKS_PER_GROUP: usize = 0x40;
    let cipher = Aes128::new_from_slice(&key).expect("AES-128 key");
    let mut data_blocks = vec![[0_u8; BLOCK_DATA_BYTES]; BLOCKS_PER_GROUP];
    for (index, block) in data_blocks.iter_mut().enumerate() {
        let start = index * BLOCK_DATA_BYTES;
        if start < decrypted.len() {
            let end = (start + BLOCK_DATA_BYTES).min(decrypted.len());
            block[..end - start].copy_from_slice(&decrypted[start..end]);
        }
    }
    let mut hash_blocks = vec![[0_u8; BLOCK_HEADER_BYTES]; BLOCKS_PER_GROUP];
    for (index, hash_block) in hash_blocks.iter_mut().enumerate() {
        for hash_index in 0..31 {
            let digest =
                Sha1::digest(&data_blocks[index][hash_index * 0x400..(hash_index + 1) * 0x400]);
            hash_block[hash_index * 20..(hash_index + 1) * 20].copy_from_slice(&digest);
        }
    }
    for group in 0..8 {
        let first = group * 8;
        let mut h1 = [0_u8; 8 * 20];
        for index in 0..8 {
            let digest = Sha1::digest(&hash_blocks[first + index][..31 * 20]);
            h1[index * 20..(index + 1) * 20].copy_from_slice(&digest);
        }
        for hash_block in hash_blocks.iter_mut().skip(first).take(8) {
            hash_block[0x280..0x320].copy_from_slice(&h1);
        }
        let digest = Sha1::digest(h1);
        hash_blocks[0][0x340 + group * 20..0x340 + (group + 1) * 20].copy_from_slice(&digest);
    }
    let h2 = hash_blocks[0][0x340..0x3e0].to_owned();
    for hash_block in hash_blocks.iter_mut().skip(1) {
        hash_block[0x340..0x3e0].copy_from_slice(&h2);
    }

    let mut encrypted = vec![0_u8; BLOCKS_PER_GROUP * BLOCK_TOTAL_BYTES];
    for index in 0..BLOCKS_PER_GROUP {
        let offset = index * BLOCK_TOTAL_BYTES;
        cbc_encrypt(
            &cipher,
            &hash_blocks[index],
            &mut encrypted[offset..offset + BLOCK_HEADER_BYTES],
            [0_u8; 16],
        );
        let mut iv = [0_u8; 16];
        iv.copy_from_slice(&encrypted[offset + 0x3d0..offset + 0x3e0]);
        cbc_encrypt(
            &cipher,
            &data_blocks[index],
            &mut encrypted[offset + BLOCK_HEADER_BYTES..offset + BLOCK_TOTAL_BYTES],
            iv,
        );
    }
    encrypted
}

fn partitioned_wii_rvz_image() -> (Vec<u8>, Vec<u8>) {
    const LOGICAL_BYTES: usize = 0x80000;
    const PARTITION_DATA_START: usize = 0x58000;
    const PARTITION_DATA_END: usize = 0x78000;
    const CHUNK_BYTES: usize = 0x8000;
    let key = [0x42_u8; 16];
    let mut logical = build_valid_wii_image();
    set_u32_be(&mut logical, 0x50000 + 0x2b8, 0x8000 >> 2);
    set_u32_be(&mut logical, 0x50000 + 0x2bc, 0x20000 >> 2);
    let decrypted = (0..0x1f000)
        .map(|index| (index as u8).wrapping_mul(3))
        .collect::<Vec<_>>();
    let encrypted = encrypted_wii_partition_group(&decrypted, key);
    logical[PARTITION_DATA_START..PARTITION_DATA_END].copy_from_slice(&encrypted[..0x20000]);
    assert_eq!(logical.len(), LOGICAL_BYTES);

    let head_size = 0x48_u64;
    let disc_size = 0xdc_u64;
    let part_offset = head_size + disc_size;
    let raw_offset = part_offset + 0x30;
    let group_offset = raw_offset + 2 * 24;
    let data_offset = (group_offset + 16 * 12).next_multiple_of(4);
    let mut result = vec![0_u8; data_offset as usize];
    result[..4].copy_from_slice(b"RVZ\x01");
    set_u32_be(&mut result, 4, 0x0100_0000);
    set_u32_be(&mut result, 8, 0x0009_0000);
    set_u32_be(&mut result, 12, disc_size as u32);
    set_u64_be(&mut result, 0x20, LOGICAL_BYTES as u64);
    let disc = head_size as usize;
    set_u32_be(&mut result, disc, 2);
    set_u32_be(&mut result, disc + 4, 0);
    set_u32_be(&mut result, disc + 12, CHUNK_BYTES as u32);
    result[disc + 16..disc + 16 + 0x80].copy_from_slice(&logical[..0x80]);
    set_u32_be(&mut result, disc + 0x90, 1);
    set_u32_be(&mut result, disc + 0x94, 0x30);
    set_u64_be(&mut result, disc + 0x98, part_offset);
    set_u32_be(&mut result, disc + 0xb4, 2);
    set_u64_be(&mut result, disc + 0xb8, raw_offset);
    set_u32_be(&mut result, disc + 0xc0, 48);
    set_u32_be(&mut result, disc + 0xc4, 16);
    set_u64_be(&mut result, disc + 0xc8, group_offset);
    set_u32_be(&mut result, disc + 0xd0, 16 * 12);

    let part = part_offset as usize;
    result[part..part + 16].copy_from_slice(&key);
    set_u32_be(&mut result, part + 16, 11);
    set_u32_be(&mut result, part + 20, 4);
    set_u32_be(&mut result, part + 24, 11);
    set_u32_be(&mut result, part + 28, 4);

    set_u64_be(&mut result, raw_offset as usize, 0);
    set_u64_be(
        &mut result,
        raw_offset as usize + 8,
        PARTITION_DATA_START as u64,
    );
    set_u32_be(&mut result, raw_offset as usize + 16, 0);
    set_u32_be(&mut result, raw_offset as usize + 20, 11);
    set_u64_be(
        &mut result,
        raw_offset as usize + 24,
        PARTITION_DATA_END as u64,
    );
    set_u64_be(
        &mut result,
        raw_offset as usize + 32,
        (LOGICAL_BYTES - PARTITION_DATA_END) as u64,
    );
    set_u32_be(&mut result, raw_offset as usize + 40, 15);
    set_u32_be(&mut result, raw_offset as usize + 44, 1);

    let mut payloads = Vec::with_capacity(16);
    for index in 0..11 {
        payloads.push(logical[index * CHUNK_BYTES..(index + 1) * CHUNK_BYTES].to_vec());
    }
    for index in 0..4 {
        let start = index * 0x7c00;
        let mut payload = vec![0_u8; 4 + 0x7c00];
        payload[4..].copy_from_slice(&decrypted[start..start + 0x7c00]);
        payloads.push(payload);
    }
    payloads.push(logical[PARTITION_DATA_END..].to_vec());
    let mut locations = Vec::with_capacity(payloads.len());
    for payload in &payloads {
        let location = result.len().next_multiple_of(4);
        result.resize(location, 0);
        locations.push(location as u64);
        result.extend_from_slice(payload);
    }
    for (index, (&location, payload)) in locations.iter().zip(&payloads).enumerate() {
        let offset = group_offset as usize + index * 12;
        set_u32_be(&mut result, offset, (location / 4) as u32);
        set_u32_be(&mut result, offset + 4, payload.len() as u32);
    }
    let file_size = result.len() as u64;
    set_u64_be(&mut result, 0x28, file_size);
    (result, logical)
}

fn rvz_image(logical: &[u8], compression: u32) -> Vec<u8> {
    assert!(logical.len().is_multiple_of(CHUNK_BYTES));
    let group_count = logical.len() / CHUNK_BYTES;
    let head_size = 0x48;
    let disc_size = 0xdc;
    let raw_data_offset = head_size + disc_size;
    let group_offset = raw_data_offset + 24;
    let data_offset = group_offset + group_count * 12;
    let mut result = vec![0_u8; data_offset];
    result[..4].copy_from_slice(b"WIA\x01");
    set_u32_be(&mut result, 4, 0x0100_0000);
    set_u32_be(&mut result, 8, 0x0009_0000);
    set_u32_be(&mut result, 12, disc_size as u32);
    set_u64_be(&mut result, 0x20, logical.len() as u64);
    set_u64_be(&mut result, 0x28, 0);

    let disc = head_size;
    let disc_type = if logical[0x18..0x1c] == [0x5d, 0x1c, 0x9e, 0xa3] {
        2
    } else {
        1
    };
    set_u32_be(&mut result, disc, disc_type);
    set_u32_be(&mut result, disc + 4, compression);
    set_u32_be(&mut result, disc + 8, 1);
    set_u32_be(&mut result, disc + 12, CHUNK_BYTES as u32);
    result[disc + 16..disc + 16 + 0x80].copy_from_slice(&logical[..0x80]);
    set_u32_be(&mut result, disc + 0x90, 0);
    set_u32_be(&mut result, disc + 0x94, 0);
    set_u64_be(&mut result, disc + 0x98, 0);
    set_u32_be(&mut result, disc + 0xb4, 1);
    set_u64_be(&mut result, disc + 0xb8, raw_data_offset as u64);
    set_u32_be(&mut result, disc + 0xc0, 24);
    set_u32_be(&mut result, disc + 0xc4, group_count as u32);
    set_u64_be(&mut result, disc + 0xc8, group_offset as u64);
    set_u32_be(&mut result, disc + 0xd0, (group_count * 12) as u32);

    set_u64_be(&mut result, raw_data_offset, 0);
    set_u64_be(&mut result, raw_data_offset + 8, logical.len() as u64);
    set_u32_be(&mut result, raw_data_offset + 16, 0);
    set_u32_be(&mut result, raw_data_offset + 20, group_count as u32);

    for group in 0..group_count {
        let group_offset = group_offset + group * 12;
        let data_offset = data_offset + group * CHUNK_BYTES;
        set_u32_be(&mut result, group_offset, (data_offset / 4) as u32);
        set_u32_be(&mut result, group_offset + 4, CHUNK_BYTES as u32);
        set_u32_be(&mut result, group_offset + 8, 0);
    }
    result.extend_from_slice(logical);
    let file_size = result.len() as u64;
    set_u64_be(&mut result, 0x28, file_size);
    result
}

fn zstd_rvz_image(logical: &[u8]) -> Vec<u8> {
    assert_eq!(logical.len(), CHUNK_BYTES);
    let raw_data_offset = 0x48 + 0xdc;
    let raw_table = {
        let mut table = vec![0_u8; 24];
        set_u64_be(&mut table, 8, logical.len() as u64);
        set_u32_be(&mut table, 20, 1);
        compress_to_vec(table.as_slice(), CompressionLevel::Fastest)
    };
    let compressed_logical = compress_to_vec(logical, CompressionLevel::Fastest);
    let mut group_data_offset = (raw_data_offset + raw_table.len() as u64 + 32).next_multiple_of(4);
    let (group_table, group_data_offset) = loop {
        let mut group = vec![0_u8; 12];
        set_u32_be(&mut group, 0, (group_data_offset / 4) as u32);
        set_u32_be(&mut group, 4, 0x8000_0000 | compressed_logical.len() as u32);
        let compressed_group = compress_to_vec(group.as_slice(), CompressionLevel::Fastest);
        let next_data_offset =
            (raw_data_offset + raw_table.len() as u64 + compressed_group.len() as u64)
                .next_multiple_of(4);
        if next_data_offset == group_data_offset {
            break (compressed_group, group_data_offset);
        }
        group_data_offset = next_data_offset;
    };
    let mut result = vec![0_u8; raw_data_offset as usize];
    result[..4].copy_from_slice(b"WIA\x01");
    set_u32_be(&mut result, 4, 0x0100_0000);
    set_u32_be(&mut result, 8, 0x0009_0000);
    set_u32_be(&mut result, 12, 0xdc);
    set_u64_be(&mut result, 0x20, logical.len() as u64);
    let disc = 0x48;
    set_u32_be(&mut result, disc, 1);
    set_u32_be(&mut result, disc + 4, 5);
    set_u32_be(&mut result, disc + 12, CHUNK_BYTES as u32);
    result[disc + 16..disc + 16 + 0x80].copy_from_slice(&logical[..0x80]);
    set_u32_be(&mut result, disc + 0xb4, 1);
    set_u64_be(&mut result, disc + 0xb8, raw_data_offset);
    set_u32_be(&mut result, disc + 0xc0, raw_table.len() as u32);
    set_u32_be(&mut result, disc + 0xc4, 1);
    set_u64_be(
        &mut result,
        disc + 0xc8,
        raw_data_offset + raw_table.len() as u64,
    );
    set_u32_be(&mut result, disc + 0xd0, group_table.len() as u32);
    result.extend_from_slice(&raw_table);
    result.extend_from_slice(&group_table);
    result.resize(group_data_offset as usize, 0);
    result.extend_from_slice(&compressed_logical);
    let file_size = result.len() as u64;
    set_u64_be(&mut result, 0x28, file_size);
    result
}

#[test]
fn complete_gamecube_and_wii_rvz_reconstruct_native_identity() {
    let fixtures = [
        (
            "gamecube-rvz",
            build_valid_gamecube_image(),
            PlatformId::NintendoGameCube,
            ContentType::OpticalDiscGameCube,
        ),
        (
            "wii-rvz",
            build_valid_wii_image(),
            PlatformId::NintendoWii,
            ContentType::OpticalDiscWii,
        ),
    ];
    for (fixture_name, logical, expected_platform, expected_content_type) in fixtures {
        let mut native_reader = MemoryReader::new(logical.clone());
        let native = recognize_native_optical(&mut native_reader).expect("native disc");
        let actual = recognize(rvz_image(&logical, 0), 100_000_000, 100_000_000)
            .unwrap_or_else(|error| panic!("RVZ {fixture_name}: {error:?}"));
        assert_eq!(
            native.platform(),
            expected_platform,
            "{fixture_name} native platform"
        );
        assert_eq!(
            native.content_type(),
            expected_content_type,
            "{fixture_name} native content type"
        );
        assert_eq!(
            actual.platform(),
            expected_platform,
            "{fixture_name} RVZ platform"
        );
        assert_eq!(
            actual.content_type(),
            expected_content_type,
            "{fixture_name} RVZ content type"
        );
        assert_eq!(actual.identity_digest(), native.identity_digest());
        assert_eq!(actual.source_representation(), "rvz");
    }
}

#[test]
fn rvz_zstandard_groups_and_metadata_reuse_gamecube_identity() {
    let logical = build_valid_gamecube_image();
    let mut native_reader = MemoryReader::new(logical.clone());
    let native = recognize_native_optical(&mut native_reader).expect("native disc");
    let actual =
        recognize(zstd_rvz_image(&logical), 100_000_000, 100_000_000).expect("zstandard RVZ disc");
    assert_eq!(actual.identity_digest(), native.identity_digest());
    assert_eq!(actual.source_representation(), "rvz");
}

#[test]
fn rvz_rejects_missing_or_unreconstructable_data_and_bad_hash_fields() {
    let logical = build_valid_gamecube_image();
    let mut missing = rvz_image(&logical, 0);
    missing.truncate(missing.len() - CHUNK_BYTES);
    assert!(matches!(
        recognize(missing, 100_000_000, 100_000_000),
        Err(OpticalError::Malformed | OpticalError::Truncated | OpticalError::ReadFailure)
    ));

    let mut invalid_group = rvz_image(&logical, 0);
    let group_offset = 0x48 + 0xdc + 24;
    invalid_group[group_offset..group_offset + 4].copy_from_slice(&u32::MAX.to_be_bytes());
    assert!(matches!(
        recognize(invalid_group, 100_000_000, 100_000_000),
        Err(OpticalError::Malformed | OpticalError::Truncated)
    ));

    let mut unsupported = rvz_image(&logical, 0);
    set_u32_be(&mut unsupported, 0x48 + 0x90, 1);
    assert_eq!(
        recognize(unsupported, 100_000_000, 100_000_000),
        Err(OpticalError::UnsupportedRepresentation)
    );

    let mut bad_hash = rvz_image(&logical, 0);
    bad_hash[0x10] = 1;
    assert_eq!(
        recognize(bad_hash, 100_000_000, 100_000_000),
        Err(OpticalError::Malformed)
    );
}

#[test]
fn rvz_honors_cancellation_and_cumulative_work_or_expansion_limits() {
    let logical = build_valid_gamecube_image();
    let staging = tempdir().expect("staging");
    let mut cancelled =
        ParsingSession::for_tests(budget(100_000_000, 100_000_000), staging.path(), || true);
    let mut reader = MemoryReader::new(rvz_image(&logical, 0));
    assert_eq!(
        recognize_rvz(&mut reader, &mut cancelled),
        Err(OpticalError::Cancelled)
    );

    assert!(matches!(
        recognize(rvz_image(&logical, 0), 1, 100_000_000),
        Err(OpticalError::ResourceLimitExceeded)
    ));
    assert!(matches!(
        recognize(rvz_image(&logical, 0), 100_000_000, 1),
        Err(OpticalError::ResourceLimitExceeded)
    ));
}

#[test]
fn partitioned_wii_rvz_reconstructs_existing_native_identity() {
    let (rvz, logical) = partitioned_wii_rvz_image();
    let mut native_reader = MemoryReader::new(logical);
    let native = recognize_native_optical(&mut native_reader).expect("native Wii disc");
    let actual = recognize(rvz, 100_000_000, 100_000_000).expect("partitioned Wii RVZ disc");
    assert_eq!(actual.platform(), native.platform());
    assert_eq!(actual.content_type(), native.content_type());
    assert_eq!(actual.identity_digest(), native.identity_digest());
}
