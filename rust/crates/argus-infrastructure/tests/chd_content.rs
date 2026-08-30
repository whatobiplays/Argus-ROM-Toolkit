use std::io::Cursor;

use argus_application::TransformationBudget;
use argus_infrastructure::content::{
    ContentReadError, ContentReader, OpticalDescriptor, OpticalError, OpticalSource,
    ParsingSession, canonicalize_descriptor, parse_cue, parse_gdi, recognize_chd,
    recognize_native_optical,
};
use tempfile::tempdir;

const ISO_SECTOR_BYTES: usize = 2_048;
const CD_FRAME_BYTES: usize = 2_448;

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

fn budget(max_work: u64) -> TransformationBudget {
    TransformationBudget::new(
        128 * 1024 * 1024,
        256 * 1024 * 1024,
        65_536,
        4,
        128 * 1024 * 1024,
        max_work,
    )
}

fn recognize(
    bytes: Vec<u8>,
    max_work: u64,
) -> Result<argus_infrastructure::content::OpticalRecognition, OpticalError> {
    let staging = tempdir().expect("staging");
    let mut session = ParsingSession::for_tests(budget(max_work), staging.path(), || false);
    let mut reader = MemoryReader::new(bytes);
    recognize_chd(&mut reader, &mut session)
}

fn set_u32_le(bytes: &mut [u8], offset: usize, value: u32) {
    bytes[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
}

fn set_u32_be(bytes: &mut [u8], offset: usize, value: u32) {
    bytes[offset..offset + 4].copy_from_slice(&value.to_be_bytes());
}

fn set_u64_be(bytes: &mut [u8], offset: usize, value: u64) {
    bytes[offset..offset + 8].copy_from_slice(&value.to_be_bytes());
}

fn set_iso_both_u16(bytes: &mut [u8], offset: usize, value: u16) {
    bytes[offset..offset + 2].copy_from_slice(&value.to_le_bytes());
    bytes[offset + 2..offset + 4].copy_from_slice(&value.to_be_bytes());
}

fn set_iso_both_u32(bytes: &mut [u8], offset: usize, value: u32) {
    set_u32_le(bytes, offset, value);
    set_u32_be(bytes, offset + 4, value);
}

fn write_iso_dir_record(
    image: &mut [u8],
    offset: usize,
    name: &[u8],
    extent: u32,
    size: u32,
    flags: u8,
) -> usize {
    let record_length = 33 + name.len() + usize::from(name.len().is_multiple_of(2));
    image[offset..offset + record_length].fill(0);
    image[offset] = record_length as u8;
    set_iso_both_u32(&mut image[offset..], 2, extent);
    set_iso_both_u32(&mut image[offset..], 10, size);
    image[offset + 25] = flags;
    image[offset + 28..offset + 30].copy_from_slice(&1_u16.to_le_bytes());
    image[offset + 30..offset + 32].copy_from_slice(&1_u16.to_be_bytes());
    image[offset + 32] = name.len() as u8;
    image[offset + 33..offset + 33 + name.len()].copy_from_slice(name);
    record_length
}

fn base_iso(sector_count: usize) -> Vec<u8> {
    let mut image = vec![0_u8; sector_count * ISO_SECTOR_BYTES];
    let pvd_offset = 16 * ISO_SECTOR_BYTES;
    image[pvd_offset] = 1;
    image[pvd_offset + 1..pvd_offset + 6].copy_from_slice(b"CD001");
    image[pvd_offset + 6] = 1;
    image[pvd_offset + 40..pvd_offset + 48].copy_from_slice(b"ARGUSISO");
    set_iso_both_u32(&mut image[pvd_offset..], 80, sector_count as u32);
    set_iso_both_u16(&mut image[pvd_offset..], 120, 1);
    set_iso_both_u16(&mut image[pvd_offset..], 124, 1);
    set_iso_both_u16(&mut image[pvd_offset..], 128, ISO_SECTOR_BYTES as u16);
    set_iso_both_u32(&mut image[pvd_offset..], 132, 10);
    set_u32_le(&mut image[pvd_offset..], 140, 18);
    set_u32_be(&mut image[pvd_offset..], 148, 18);
    write_iso_dir_record(
        &mut image,
        pvd_offset + 156,
        &[0],
        20,
        ISO_SECTOR_BYTES as u32,
        0x02,
    );
    let terminator_offset = 17 * ISO_SECTOR_BYTES;
    image[terminator_offset] = 0xff;
    image[terminator_offset + 1..terminator_offset + 6].copy_from_slice(b"CD001");
    image[terminator_offset + 6] = 1;
    let path_table_offset = 18 * ISO_SECTOR_BYTES;
    image[path_table_offset] = 1;
    set_u32_le(&mut image[path_table_offset..], 2, 20);
    image[path_table_offset + 6..path_table_offset + 8].copy_from_slice(&1_u16.to_le_bytes());
    image
}

fn build_iso_with_files(files: Vec<(String, Vec<u8>)>) -> Vec<u8> {
    let mut image = base_iso(64);
    let directory_offset = 20 * ISO_SECTOR_BYTES;
    let mut directory_cursor = directory_offset;
    directory_cursor += write_iso_dir_record(
        &mut image,
        directory_cursor,
        &[0],
        20,
        ISO_SECTOR_BYTES as u32,
        0x02,
    );
    directory_cursor += write_iso_dir_record(
        &mut image,
        directory_cursor,
        &[1],
        20,
        ISO_SECTOR_BYTES as u32,
        0x02,
    );
    let mut extent = 21_u32;
    for (name, data) in files {
        let sector_count = data.len().max(1).div_ceil(ISO_SECTOR_BYTES);
        let offset = extent as usize * ISO_SECTOR_BYTES;
        image[offset..offset + data.len()].copy_from_slice(&data);
        directory_cursor += write_iso_dir_record(
            &mut image,
            directory_cursor,
            name.as_bytes(),
            extent,
            data.len() as u32,
            0,
        );
        extent += sector_count as u32;
    }
    assert!(directory_cursor <= directory_offset + ISO_SECTOR_BYTES);
    image
}

fn psx_exe() -> Vec<u8> {
    let mut executable = vec![0_u8; 0x800];
    executable[..8].copy_from_slice(b"PS-X EXE");
    executable
}

fn build_ps1_iso() -> Vec<u8> {
    build_iso_with_files(vec![
        (
            "SYSTEM.CNF;1".to_owned(),
            b"BOOT = cdrom:\\SLUS_000.01;1\n".to_vec(),
        ),
        ("SLUS_000.01;1".to_owned(), psx_exe()),
    ])
}

fn build_ps2_cd_iso() -> Vec<u8> {
    build_iso_with_files(vec![
        (
            "SYSTEM.CNF;1".to_owned(),
            b"BOOT2 = cdrom0:\\SCUS_000.01;1\nVER = 1.00\nVMODE = NTSC\n".to_vec(),
        ),
        ("SCUS_000.01;1".to_owned(), vec![0_u8; 0x100]),
    ])
}

fn build_ps2_iso() -> Vec<u8> {
    let mut image = build_iso_with_files(vec![
        (
            "SYSTEM.CNF;1".to_owned(),
            b"BOOT2 = cdrom0:\\SCUS_000.01;1\nVER = 1.00\nVMODE = NTSC\n".to_vec(),
        ),
        ("SCUS_000.01;1".to_owned(), vec![0_u8; 0x100]),
    ]);
    image.resize(320 * ISO_SECTOR_BYTES, 0);
    set_iso_both_u32(&mut image[16 * ISO_SECTOR_BYTES..], 80, 320);
    image[256 * ISO_SECTOR_BYTES + 1..256 * ISO_SECTOR_BYTES + 6].copy_from_slice(b"BEA01");
    image[257 * ISO_SECTOR_BYTES + 1..257 * ISO_SECTOR_BYTES + 6].copy_from_slice(b"NSR02");
    image
}

fn build_sega_cd_iso(identifier: &[u8]) -> Vec<u8> {
    let mut image = build_iso_with_files(Vec::new());
    image[..identifier.len()].copy_from_slice(identifier);
    set_u32_be(&mut image, 0x30, 0x200);
    set_u32_be(&mut image, 0x34, 0x600);
    set_u32_be(&mut image, 0x40, 0x800);
    set_u32_be(&mut image, 0x44, 0x7200);
    image[0x100..0x104].copy_from_slice(b"SEGA");
    image
}

fn build_saturn_iso() -> Vec<u8> {
    let mut image = build_iso_with_files(Vec::new());
    image[..16].copy_from_slice(b"SEGA SEGASATURN ");
    image[0x20..0x2b].copy_from_slice(b"SATURN-BOOT");
    image
}

fn build_dreamcast_iso() -> Vec<u8> {
    let mut image = build_iso_with_files(vec![("1ST_READ.BIN;1".to_owned(), vec![0_u8; 0x200])]);
    image[..16].copy_from_slice(b"SEGA SEGAKATANA ");
    image[0x10..0x20].copy_from_slice(b"SEGA ENTERPRISES");
    image[0x20..0x30].copy_from_slice(b"Dreamcast GD-ROM");
    image[0x40..0x48].copy_from_slice(b"HDR-0000");
    image[0x4a..0x4e].copy_from_slice(b"V1.0");
    image[0x50..0x58].copy_from_slice(b"20260826");
    image[0x60..0x6c].copy_from_slice(b"1ST_READ.BIN");
    image
}

fn psp_param_sfo() -> Vec<u8> {
    let bootable = 1_u32.to_le_bytes();
    let values = [
        ("DISC_ID", b"ULUS-00000\0".as_slice(), 0x0204_u16),
        ("BOOTABLE", bootable.as_slice(), 0x0404_u16),
        ("CATEGORY", b"UG\0".as_slice(), 0x0204_u16),
        ("PSP_SYSTEM_VER", b"6.61\0".as_slice(), 0x0204_u16),
    ];
    let key_bytes: Vec<u8> = values
        .iter()
        .flat_map(|(key, _, _)| key.as_bytes().iter().copied().chain(std::iter::once(0)))
        .collect();
    let key_start = 20 + values.len() * 16;
    let data_start = key_start + key_bytes.len();
    let data_bytes: usize = values.iter().map(|(_, value, _)| value.len()).sum();
    let mut result = vec![0_u8; data_start + data_bytes];
    result[..4].copy_from_slice(b"\0PSF");
    set_u32_le(&mut result, 8, key_start as u32);
    set_u32_le(&mut result, 12, data_start as u32);
    set_u32_le(&mut result, 16, values.len() as u32);
    result[key_start..data_start].copy_from_slice(&key_bytes);
    let mut key_offset = 0_u16;
    let mut data_offset = 0_u32;
    for (index, (_, value, value_type)) in values.iter().enumerate() {
        let entry_offset = 20 + index * 16;
        result[entry_offset..entry_offset + 2].copy_from_slice(&key_offset.to_le_bytes());
        result[entry_offset + 2..entry_offset + 4].copy_from_slice(&value_type.to_le_bytes());
        set_u32_le(&mut result, entry_offset + 4, value.len() as u32);
        set_u32_le(&mut result, entry_offset + 8, value.len() as u32);
        set_u32_le(&mut result, entry_offset + 12, data_offset);
        let start = data_start + data_offset as usize;
        result[start..start + value.len()].copy_from_slice(value);
        key_offset += values[index].0.len() as u16 + 1;
        data_offset += value.len() as u32;
    }
    result
}

fn build_psp_iso() -> Vec<u8> {
    let mut image = base_iso(64);
    let param = psp_param_sfo();
    let eboot = vec![0_u8; 0x100];
    let umd_data = b"ULUS-00000\n";
    let mut directory = Vec::new();
    let root = 20 * ISO_SECTOR_BYTES;
    let mut cursor = root;
    cursor += write_iso_dir_record(&mut image, cursor, &[0], 20, 2048, 2);
    cursor += write_iso_dir_record(&mut image, cursor, &[1], 20, 2048, 2);
    cursor += write_iso_dir_record(&mut image, cursor, b"PSP_GAME", 21, 2048, 2);
    cursor += write_iso_dir_record(
        &mut image,
        cursor,
        b"UMD_DATA.BIN;1",
        25,
        umd_data.len() as u32,
        0,
    );
    directory.push((
        21_u32,
        vec![
            (b"PARAM.SFO;1".as_slice(), 22_u32, param.len() as u32, 0),
            (b"SYSDIR".as_slice(), 23_u32, 2048, 2),
        ],
    ));
    directory.push((
        23_u32,
        vec![(b"EBOOT.BIN;1".as_slice(), 24_u32, eboot.len() as u32, 0)],
    ));
    let root_offset = 22 * ISO_SECTOR_BYTES;
    image[root_offset..root_offset + param.len()].copy_from_slice(&param);
    image[24 * ISO_SECTOR_BYTES..24 * ISO_SECTOR_BYTES + eboot.len()].copy_from_slice(&eboot);
    image[25 * ISO_SECTOR_BYTES..25 * ISO_SECTOR_BYTES + umd_data.len()].copy_from_slice(umd_data);
    for (extent, entries) in directory {
        let mut offset = extent as usize * ISO_SECTOR_BYTES;
        image[offset..offset + ISO_SECTOR_BYTES].fill(0);
        offset += write_iso_dir_record(&mut image, offset, &[0], extent, 2048, 2);
        offset += write_iso_dir_record(&mut image, offset, &[1], extent, 2048, 2);
        for (name, entry_extent, size, flags) in entries {
            offset += write_iso_dir_record(&mut image, offset, name, entry_extent, size, flags);
        }
        assert!(offset <= extent as usize * ISO_SECTOR_BYTES + ISO_SECTOR_BYTES);
    }
    let _ = cursor;
    image
}

fn mode1_frames(iso: &[u8]) -> Vec<u8> {
    iso.chunks_exact(ISO_SECTOR_BYTES)
        .flat_map(|sector| {
            let mut frame = vec![0_u8; CD_FRAME_BYTES];
            frame[..12].copy_from_slice(&[
                0, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0,
            ]);
            frame[15] = 1;
            frame[16..16 + ISO_SECTOR_BYTES].copy_from_slice(sector);
            frame
        })
        .collect()
}

fn metadata_entry(tag: &[u8; 4], value: &[u8], next: u64) -> Vec<u8> {
    let mut result = Vec::with_capacity(16 + value.len());
    result.extend_from_slice(tag);
    result.extend_from_slice(&(value.len() as u32).to_be_bytes());
    result.extend_from_slice(&next.to_be_bytes());
    result.extend_from_slice(value);
    result
}

fn chd_v5_sparse(
    logical_bytes: u64,
    hunk_bytes: u32,
    unit_bytes: u32,
    metadata: Vec<([u8; 4], Vec<u8>)>,
    chunks: Vec<(u32, Vec<u8>)>,
) -> Vec<u8> {
    let hunk_count = logical_bytes.div_ceil(u64::from(hunk_bytes)) as u32;
    let map_offset = 124_u64;
    let metadata_offset = map_offset + u64::from(hunk_count) * 4;
    let mut metadata_bytes = Vec::new();
    for (index, (tag, value)) in metadata.iter().enumerate() {
        let entry_offset = metadata_offset + metadata_bytes.len() as u64;
        let next = metadata
            .get(index + 1)
            .map(|_| entry_offset + 16 + value.len() as u64)
            .unwrap_or(0);
        metadata_bytes.extend(metadata_entry(tag, value, next));
    }
    let mut result = vec![0_u8; (metadata_offset as usize) + metadata_bytes.len()];
    let data_alignment = usize::try_from(hunk_bytes).expect("hunk bytes");
    let aligned_data_offset = result.len().div_ceil(data_alignment) * data_alignment;
    result.resize(aligned_data_offset, 0);
    let mut map = vec![0_u8; hunk_count as usize * 4];
    for (hunk, bytes) in chunks {
        assert_eq!(bytes.len(), hunk_bytes as usize);
        let data_offset = result.len();
        assert!(data_offset.is_multiple_of(data_alignment));
        let map_offset_in_bytes = hunk as usize * 4;
        map[map_offset_in_bytes..map_offset_in_bytes + 4].copy_from_slice(
            &u32::try_from(data_offset / data_alignment)
                .expect("map offset")
                .to_be_bytes(),
        );
        result.extend_from_slice(&bytes);
    }
    result[metadata_offset as usize..metadata_offset as usize + metadata_bytes.len()]
        .copy_from_slice(&metadata_bytes);
    result[map_offset as usize..map_offset as usize + map.len()].copy_from_slice(&map);

    let mut header = vec![0_u8; 124];
    header[..8].copy_from_slice(b"MComprHD");
    header[8..12].copy_from_slice(&124_u32.to_be_bytes());
    header[12..16].copy_from_slice(&5_u32.to_be_bytes());
    header[32..40].copy_from_slice(&logical_bytes.to_be_bytes());
    header[40..48].copy_from_slice(&map_offset.to_be_bytes());
    header[48..56].copy_from_slice(&metadata_offset.to_be_bytes());
    header[56..60].copy_from_slice(&hunk_bytes.to_be_bytes());
    header[60..64].copy_from_slice(&unit_bytes.to_be_bytes());
    result[..124].copy_from_slice(&header);
    result
}

fn cd_chd(iso: &[u8]) -> Vec<u8> {
    let frames = mode1_frames(iso);
    let hunk_bytes = CD_FRAME_BYTES as u32 * 4;
    chd_v5_sparse(
        frames.len() as u64,
        hunk_bytes,
        CD_FRAME_BYTES as u32,
        vec![(
            *b"CHT2",
            format!(
                "TRACK:1 TYPE:MODE1 SUBTYPE:NONE FRAMES:{} PREGAP:0 PGTYPE:MODE1 PGSUB:NONE POSTGAP:0\0",
                iso.len() / ISO_SECTOR_BYTES
            )
            .into_bytes(),
        )],
        frames
            .chunks_exact(hunk_bytes as usize)
            .enumerate()
            .map(|(index, bytes)| (index as u32, bytes.to_vec()))
            .collect(),
    )
}

fn dvd_chd(iso: &[u8], tag: [u8; 4]) -> Vec<u8> {
    let hunk_bytes = ISO_SECTOR_BYTES as u32 * 4;
    chd_v5_sparse(
        iso.len() as u64,
        hunk_bytes,
        ISO_SECTOR_BYTES as u32,
        vec![(tag, vec![1])],
        iso.chunks_exact(hunk_bytes as usize)
            .enumerate()
            .map(|(index, bytes)| (index as u32, bytes.to_vec()))
            .collect(),
    )
}

#[test]
fn chd_cd_reuses_native_cd_identity() {
    for (fixture_name, native_bytes, expected_platform) in [
        (
            "sega-cd",
            build_sega_cd_iso(b"SEGADISCSYSTEM"),
            argus_application::PlatformId::SegaCd,
        ),
        (
            "sega-saturn",
            build_saturn_iso(),
            argus_application::PlatformId::SegaSaturn,
        ),
        (
            "playstation",
            build_ps1_iso(),
            argus_application::PlatformId::SonyPlaystation,
        ),
        (
            "playstation-2-cd",
            build_ps2_cd_iso(),
            argus_application::PlatformId::SonyPlaystation2,
        ),
    ] {
        let mut native = MemoryReader::new(native_bytes.clone());
        let expected = recognize_native_optical(&mut native)
            .unwrap_or_else(|error| panic!("{fixture_name} native: {error:?}"));
        assert_eq!(expected.platform(), expected_platform, "{fixture_name}");
        assert_eq!(
            expected.content_type(),
            argus_application::ContentType::OpticalDiscCd,
            "{fixture_name}"
        );
        let actual = recognize(cd_chd(&native_bytes), 1_000_000)
            .unwrap_or_else(|error| panic!("{fixture_name} CHD: {error:?}"));
        assert_eq!(actual.platform(), expected_platform, "{fixture_name}");
        assert_eq!(
            actual.content_type(),
            argus_application::ContentType::OpticalDiscCd,
            "{fixture_name}"
        );
        assert_eq!(
            actual.identity_digest(),
            expected.identity_digest(),
            "{fixture_name}"
        );
        assert_eq!(actual.source_representation(), "chd-cd", "{fixture_name}");
    }
}

#[test]
fn chd_dvd_and_umd_use_existing_native_optical_identities() {
    for (iso, expected_representation) in
        [(build_ps2_iso(), "chd-dvd"), (build_psp_iso(), "chd-umd")]
    {
        let mut native = MemoryReader::new(iso.clone());
        let expected = recognize_native_optical(&mut native).expect("native optical");
        let tag = if expected_representation == "chd-umd" {
            *b"UMD "
        } else {
            *b"DVD "
        };
        let actual = recognize(dvd_chd(&iso, tag), 2_000_000).expect("CHD optical");
        assert_eq!(actual.platform(), expected.platform());
        assert_eq!(actual.content_type(), expected.content_type());
        assert_eq!(actual.identity_digest(), expected.identity_digest());
        assert_eq!(actual.source_representation(), expected_representation);
    }
}

#[test]
fn chd_direct_media_tags_must_match_native_media_classification() {
    let psp = build_psp_iso();
    assert!(matches!(
        recognize(dvd_chd(&psp, *b"DVD "), 2_000_000),
        Err(OpticalError::UnsupportedRepresentation)
    ));

    let dvd = build_ps2_iso();
    assert!(matches!(
        recognize(dvd_chd(&dvd, *b"UMD "), 2_000_000),
        Err(OpticalError::UnsupportedRepresentation)
    ));
}

#[test]
fn chd_gd_uses_validated_track_metadata_and_existing_gd_identity() {
    let high = build_dreamcast_iso();
    let low_frame_count = 45_000_u64;
    let high_frames = mode1_frames(&high);
    let hunk_bytes = CD_FRAME_BYTES as u32 * 4;
    let first_high_hunk = (low_frame_count * CD_FRAME_BYTES as u64 / u64::from(hunk_bytes)) as u32;
    let mut chunks = Vec::new();
    for (offset, bytes) in high_frames.chunks_exact(hunk_bytes as usize).enumerate() {
        chunks.push((first_high_hunk + offset as u32, bytes.to_vec()));
    }
    let logical = low_frame_count * CD_FRAME_BYTES as u64 + high_frames.len() as u64;
    let metadata = vec![
        (
            *b"CHGD",
            format!(
                "TRACK:1 TYPE:MODE1 SUBTYPE:NONE FRAMES:{low_frame_count} PAD:44990 PREGAP:0 PGTYPE:MODE1 PGSUB:NONE POSTGAP:0\0"
            )
            .into_bytes(),
        ),
        (
            *b"CHGD",
            format!(
                "TRACK:2 TYPE:MODE1 SUBTYPE:NONE FRAMES:{} PAD:0 PREGAP:0 PGTYPE:MODE1 PGSUB:NONE POSTGAP:0\0",
                high.len() / ISO_SECTOR_BYTES
            )
            .into_bytes(),
        ),
    ];
    let chd = chd_v5_sparse(
        logical,
        hunk_bytes,
        CD_FRAME_BYTES as u32,
        metadata,
        std::mem::take(&mut chunks),
    );

    let mut native_source =
        vec![0_u8; (low_frame_count as usize + high.len() / ISO_SECTOR_BYTES) * ISO_SECTOR_BYTES];
    let high_offset = low_frame_count as usize * ISO_SECTOR_BYTES;
    native_source[high_offset..].copy_from_slice(&high);
    let descriptor =
        parse_gdi("2\n1 0 4 2048 \"low.bin\" 0\n2 45000 4 2048 \"high.bin\" 0\n").expect("GDI");
    let mut low_reader = MemoryReader::new(vec![0_u8; high_offset]);
    let mut high_reader = MemoryReader::new(high);
    let mut sources = [
        OpticalSource::new("low.bin", &mut low_reader),
        OpticalSource::new("high.bin", &mut high_reader),
    ];
    let expected = canonicalize_descriptor(&OpticalDescriptor::Gdi(descriptor), &mut sources)
        .expect("native GD");
    let actual = recognize(chd, 300_000_000).expect("CHD GD");
    assert_eq!(actual.platform(), expected.platform());
    assert_eq!(actual.content_type(), expected.content_type());
    assert_eq!(actual.identity_digest(), expected.identity_digest());
    assert_eq!(actual.source_representation(), "chd-gd");
}

#[test]
fn chd_stored_pregap_is_not_hashed_as_the_previous_track_tail() {
    let iso = build_ps1_iso();
    let all_frames = mode1_frames(&iso);
    let mut raw_frames = all_frames;
    raw_frames.extend(std::iter::repeat_n(vec![0_u8; CD_FRAME_BYTES], 4).flatten());
    assert_eq!(raw_frames.len(), 68 * CD_FRAME_BYTES);

    let hunk_bytes = CD_FRAME_BYTES as u32 * 4;
    let chd = chd_v5_sparse(
        raw_frames.len() as u64,
        hunk_bytes,
        CD_FRAME_BYTES as u32,
        vec![
            (
                *b"CHT2",
                b"TRACK:1 TYPE:MODE1 SUBTYPE:NONE FRAMES:64 PREGAP:0 PGTYPE:MODE1 PGSUB:NONE POSTGAP:0\0"
                    .to_vec(),
            ),
            (
                *b"CHT2",
                b"TRACK:2 TYPE:MODE1 SUBTYPE:NONE FRAMES:4 PREGAP:2 PGTYPE:MODE1 PGSUB:NONE POSTGAP:0\0"
                    .to_vec(),
            ),
        ],
        raw_frames
            .chunks_exact(hunk_bytes as usize)
            .enumerate()
            .map(|(index, bytes)| (index as u32, bytes.to_vec()))
            .collect(),
    );

    let mut expected_file = iso;
    expected_file.extend(std::iter::repeat_n(0_u8, 2 * ISO_SECTOR_BYTES));
    expected_file.extend(std::iter::repeat_n(0_u8, 2 * ISO_SECTOR_BYTES));
    let descriptor = parse_cue(
        "FILE \"chd-track.bin\" BINARY\nTRACK 01 MODE1/2048\nINDEX 01 00:00:00\nFILE \"chd-track.bin\" BINARY\nTRACK 02 MODE1/2048\nINDEX 00 00:00:64\nINDEX 01 00:00:66\n",
    )
    .expect("CUE descriptor");
    let mut expected_reader = MemoryReader::new(expected_file);
    let mut expected_sources = [OpticalSource::new("chd-track.bin", &mut expected_reader)];
    let expected =
        canonicalize_descriptor(&OpticalDescriptor::Cue(descriptor), &mut expected_sources)
            .expect("expected split-track identity");
    let actual = recognize(chd, 10_000_000).expect("two-track CHD");

    assert_eq!(actual.platform(), expected.platform());
    assert_eq!(actual.content_type(), expected.content_type());
    assert_eq!(actual.identity_digest(), expected.identity_digest());
    assert_eq!(actual.canonical_length(), expected.canonical_length());
}

#[test]
fn chd_metadata_budget_includes_zero_length_record_headers() {
    let iso = build_ps1_iso();
    let metadata = (0..=65_536).map(|_| (*b"NOPE", Vec::new())).collect();
    assert_eq!(
        recognize(
            chd_v5_sparse(
                iso.len() as u64,
                ISO_SECTOR_BYTES as u32 * 4,
                ISO_SECTOR_BYTES as u32,
                metadata,
                iso.chunks_exact(ISO_SECTOR_BYTES * 4)
                    .enumerate()
                    .map(|(index, bytes)| (index as u32, bytes.to_vec()))
                    .collect(),
            ),
            10_000_000
        ),
        Err(OpticalError::ResourceLimitExceeded)
    );
}

#[test]
fn chd_metadata_chain_may_link_to_a_previously_seen_lower_offset() {
    let iso = build_ps2_iso();
    let mut chd = dvd_chd(&iso, *b"DVD ");
    let first = metadata_entry(b"DVD ", &[1], 512);
    let second = metadata_entry(b"NOPE", &[], 0);
    set_u64_be(&mut chd, 48, 528);
    chd[528..528 + first.len()].copy_from_slice(&first);
    chd[512..512 + second.len()].copy_from_slice(&second);

    let actual = recognize(chd, 2_000_000).expect("backward-linked metadata");
    assert_eq!(actual.source_representation(), "chd-dvd");
}

#[test]
fn cue_stored_pregap_bytes_are_hashed_at_their_index_zero_offset() {
    let descriptor = parse_cue(
        "FILE \"disc.bin\" BINARY\nTRACK 01 MODE1/2048\nINDEX 01 00:00:00\nTRACK 02 MODE1/2048\nINDEX 00 00:00:64\nINDEX 01 00:00:65\n",
    )
    .expect("CUE descriptor");
    let track_one = build_ps1_iso();
    assert_eq!(track_one.len(), 64 * ISO_SECTOR_BYTES);
    let mut first = track_one.clone();
    first.extend(std::iter::repeat_n(0x22_u8, ISO_SECTOR_BYTES));
    first.extend(std::iter::repeat_n(0x33_u8, ISO_SECTOR_BYTES));
    let mut second = track_one;
    second.extend(std::iter::repeat_n(0x44_u8, ISO_SECTOR_BYTES));
    second.extend(std::iter::repeat_n(0x33_u8, ISO_SECTOR_BYTES));

    let first_identity = {
        let mut reader = MemoryReader::new(first);
        let mut sources = [OpticalSource::new("disc.bin", &mut reader)];
        canonicalize_descriptor(&OpticalDescriptor::Cue(descriptor.clone()), &mut sources)
            .expect("first CUE identity")
            .identity_digest()
    };
    let second_identity = {
        let mut reader = MemoryReader::new(second);
        let mut sources = [OpticalSource::new("disc.bin", &mut reader)];
        canonicalize_descriptor(&OpticalDescriptor::Cue(descriptor), &mut sources)
            .expect("second CUE identity")
            .identity_digest()
    };

    assert_ne!(first_identity, second_identity);
}

#[test]
fn chd_rejects_wrong_metadata_truncation_cancellation_and_work_exhaustion() {
    let iso = build_ps1_iso();
    let mut malformed = cd_chd(&iso);
    malformed.truncate(malformed.len() - 1);
    assert!(matches!(
        recognize(malformed, 1_000_000),
        Err(OpticalError::Malformed | OpticalError::Truncated)
    ));

    let wrong_metadata = chd_v5_sparse(
        iso.len() as u64,
        ISO_SECTOR_BYTES as u32 * 4,
        ISO_SECTOR_BYTES as u32,
        vec![(*b"NOPE", vec![1])],
        iso.chunks_exact(ISO_SECTOR_BYTES * 4)
            .enumerate()
            .map(|(index, bytes)| (index as u32, bytes.to_vec()))
            .collect(),
    );
    assert!(matches!(
        recognize(wrong_metadata, 1_000_000),
        Err(OpticalError::UnsupportedRepresentation)
    ));

    let staging = tempdir().expect("staging");
    let mut cancelled = ParsingSession::for_tests(budget(1_000_000), staging.path(), || true);
    let mut reader = MemoryReader::new(cd_chd(&iso));
    assert_eq!(
        recognize_chd(&mut reader, &mut cancelled),
        Err(OpticalError::Cancelled)
    );
    assert!(matches!(
        recognize(cd_chd(&iso), 1),
        Err(OpticalError::ResourceLimitExceeded)
    ));
}

#[test]
fn chd_accounts_for_decoded_hunk_and_output_bytes_as_parser_work() {
    let iso = build_ps1_iso();
    let chd = cd_chd(&iso);
    let legacy_work_allowance = chd.len() as u64 + 1_024;

    assert_eq!(
        recognize(chd, legacy_work_allowance),
        Err(OpticalError::ResourceLimitExceeded)
    );
}

#[test]
fn chd_fixture_builder_keeps_reader_input_seekable() {
    let iso = build_ps1_iso();
    let cursor = Cursor::new(cd_chd(&iso));
    assert!(cursor.get_ref().starts_with(b"MComprHD"));
}
