use argus_infrastructure::content::{
    ContentReadError, ContentReader, OpticalDescriptor, OpticalError, OpticalSource,
    canonicalize_descriptor, parse_cue, parse_descriptor, parse_gdi, parse_m3u,
    recognize_native_optical, recognize_native_optical_with_cancel,
};

const ISO_SECTOR_BYTES: usize = 2_048;

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

fn set_u32_le(bytes: &mut [u8], offset: usize, value: u32) {
    bytes[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
}

fn set_u32_be(bytes: &mut [u8], offset: usize, value: u32) {
    bytes[offset..offset + 4].copy_from_slice(&value.to_be_bytes());
}

fn set_iso_both_u16(bytes: &mut [u8], offset: usize, value: u16) {
    bytes[offset..offset + 2].copy_from_slice(&value.to_le_bytes());
    bytes[offset + 2..offset + 4].copy_from_slice(&value.to_be_bytes());
}

fn set_iso_both_endian(bytes: &mut [u8], offset: usize, value: u32) {
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
    assert!(record_length <= u8::MAX as usize);
    image[offset..offset + record_length].fill(0);
    image[offset] = record_length as u8;
    set_iso_both_endian(&mut image[offset..], 2, extent);
    set_iso_both_endian(&mut image[offset..], 10, size);
    image[offset + 25] = flags;
    image[offset + 28..offset + 30].copy_from_slice(&1_u16.to_le_bytes());
    image[offset + 30..offset + 32].copy_from_slice(&1_u16.to_be_bytes());
    image[offset + 32] = name.len() as u8;
    image[offset + 33..offset + 33 + name.len()].copy_from_slice(name);
    record_length
}

fn base_iso(sector_count: usize) -> Vec<u8> {
    assert!(sector_count >= 32);
    let mut image = vec![0_u8; sector_count * ISO_SECTOR_BYTES];
    let pvd_offset = 16 * ISO_SECTOR_BYTES;
    image[pvd_offset] = 1;
    image[pvd_offset + 1..pvd_offset + 6].copy_from_slice(b"CD001");
    image[pvd_offset + 6] = 1;
    image[pvd_offset + 40..pvd_offset + 48].copy_from_slice(b"ARGUSISO");
    set_iso_both_endian(&mut image[pvd_offset..], 80, sector_count as u32);
    set_iso_both_u16(&mut image[pvd_offset..], 120, 1);
    set_iso_both_u16(&mut image[pvd_offset..], 124, 1);
    set_iso_both_u16(&mut image[pvd_offset..], 128, ISO_SECTOR_BYTES as u16);
    set_iso_both_endian(&mut image[pvd_offset..], 132, 10);
    set_u32_le(&mut image[pvd_offset..], 140, 18);
    set_u32_le(&mut image[pvd_offset..], 144, 0);
    set_u32_be(&mut image[pvd_offset..], 148, 18);
    set_u32_be(&mut image[pvd_offset..], 152, 0);
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
    image[path_table_offset + 1] = 0;
    set_u32_le(&mut image[path_table_offset..], 2, 20);
    image[path_table_offset + 6..path_table_offset + 8].copy_from_slice(&1_u16.to_le_bytes());
    image[path_table_offset + 8] = 0;
    image
}

fn write_directory(image: &mut [u8], extent: u32, entries: &[(String, u32, u32, u8)]) {
    let directory_offset = extent as usize * ISO_SECTOR_BYTES;
    image[directory_offset..directory_offset + ISO_SECTOR_BYTES].fill(0);
    let mut offset = directory_offset;
    offset += write_iso_dir_record(image, offset, &[0], extent, ISO_SECTOR_BYTES as u32, 0x02);
    offset += write_iso_dir_record(image, offset, &[1], extent, ISO_SECTOR_BYTES as u32, 0x02);
    for (name, entry_extent, size, flags) in entries {
        let written =
            write_iso_dir_record(image, offset, name.as_bytes(), *entry_extent, *size, *flags);
        offset += written;
    }
    assert!(offset <= directory_offset + ISO_SECTOR_BYTES);
}

fn write_extent(image: &mut [u8], extent: u32, data: &[u8]) {
    let offset = extent as usize * ISO_SECTOR_BYTES;
    assert!(offset + data.len() <= image.len());
    image[offset..offset + data.len()].copy_from_slice(data);
}

fn build_iso_with_files(files: Vec<(String, Vec<u8>)>) -> Vec<u8> {
    let mut image = base_iso(64);
    let mut entries = Vec::with_capacity(files.len());
    let mut extent = 21_u32;
    for (name, data) in files {
        let sector_count = data.len().max(1).div_ceil(ISO_SECTOR_BYTES);
        write_extent(&mut image, extent, &data);
        entries.push((name, extent, data.len() as u32, 0));
        extent += sector_count as u32;
    }
    write_directory(&mut image, 20, &entries);
    image
}

fn cue_descriptor() -> OpticalDescriptor {
    OpticalDescriptor::Cue(
        parse_cue("FILE \"disc.bin\" BINARY\nTRACK 01 MODE1/2048\nINDEX 01 00:00:00\n")
            .expect("cue descriptor"),
    )
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

fn build_ps2_iso() -> Vec<u8> {
    build_iso_with_files(vec![
        (
            "SYSTEM.CNF;1".to_owned(),
            b"BOOT2 = cdrom0:\\SCUS_000.01;1\nVER = 1.00\nVMODE = NTSC\n".to_vec(),
        ),
        ("SCUS_000.01;1".to_owned(), vec![0_u8; 0x100]),
    ])
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
    let entry_bytes = values.len() * 16;
    let key_start = 20 + entry_bytes;
    let data_start = key_start + key_bytes.len();
    let data_bytes: usize = values.iter().map(|(_, value, _)| value.len()).sum();
    let mut result = vec![0_u8; data_start + data_bytes];
    result[..4].copy_from_slice(b"\0PSF");
    set_u32_le(&mut result, 4, 0x0001_0100);
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
        let absolute_data_offset = data_start + data_offset as usize;
        result[absolute_data_offset..absolute_data_offset + value.len()].copy_from_slice(value);
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
    write_extent(&mut image, 22, &param);
    write_extent(&mut image, 24, &eboot);
    write_extent(&mut image, 25, umd_data);
    write_directory(
        &mut image,
        20,
        &[
            ("PSP_GAME".to_owned(), 21, ISO_SECTOR_BYTES as u32, 0x02),
            ("UMD_DATA.BIN;1".to_owned(), 25, umd_data.len() as u32, 0),
        ],
    );
    write_directory(
        &mut image,
        21,
        &[
            ("PARAM.SFO;1".to_owned(), 22, param.len() as u32, 0),
            ("SYSDIR".to_owned(), 23, ISO_SECTOR_BYTES as u32, 0x02),
        ],
    );
    write_directory(
        &mut image,
        23,
        &[("EBOOT.BIN;1".to_owned(), 24, eboot.len() as u32, 0)],
    );
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
    image[0x30..0x34].copy_from_slice(b"JUE ");
    image[0x40..0x48].copy_from_slice(b"HDR-0000");
    image[0x4a..0x4e].copy_from_slice(b"V1.0");
    image[0x50..0x58].copy_from_slice(b"20260826");
    image[0x60..0x6c].copy_from_slice(b"1ST_READ.BIN");
    image[0x70..0x7f].copy_from_slice(b"ARGUS DREAMCAST");
    image
}

fn build_valid_gamecube_image() -> Vec<u8> {
    let mut image = vec![0_u8; 0x8000];
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
    let mut image = vec![0_u8; 0x80000];
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

#[test]
fn cue_parser_exposes_only_validated_dependencies_and_canonicalizes_structural_sega_cd() {
    let descriptor =
        parse_cue("FILE \"disc.bin\" BINARY\nTRACK 01 MODE1/2048\nINDEX 01 00:00:00\n")
            .expect("cue descriptor");
    assert_eq!(descriptor.dependencies(), &["disc.bin".to_owned()]);
    assert_eq!(descriptor.tracks().len(), 1);
    assert_eq!(descriptor.tracks()[0].index_one(), 0);

    let mut reader = MemoryReader::new(build_sega_cd_iso(b"SEGADISCSYSTEM"));
    let mut sources = [OpticalSource::new("disc.bin", &mut reader)];
    let result = canonicalize_descriptor(&OpticalDescriptor::Cue(descriptor), &mut sources)
        .expect("cue identity");
    assert_eq!(result.platform(), argus_application::PlatformId::SegaCd);
    assert_eq!(
        result.content_type(),
        argus_application::ContentType::OpticalDiscCd
    );
    assert_eq!(result.source_representation(), "cue-bin");
}

#[test]
fn sega_data_disc_identifier_is_not_a_game_authority() {
    let mut reader = MemoryReader::new(build_sega_cd_iso(b"SEGADATADISC"));
    assert!(recognize_native_optical(&mut reader).is_err());
}

#[test]
fn cue_saturn_and_dreamcast_use_fixed_bootstrap_locations() {
    for (image, expected_platform, expected_type) in [
        (
            build_saturn_iso(),
            argus_application::PlatformId::SegaSaturn,
            argus_application::ContentType::OpticalDiscCd,
        ),
        (
            build_dreamcast_iso(),
            argus_application::PlatformId::SegaDreamcast,
            argus_application::ContentType::OpticalDiscGd,
        ),
    ] {
        let descriptor = cue_descriptor();
        let mut reader = MemoryReader::new(image);
        let mut sources = [OpticalSource::new("disc.bin", &mut reader)];
        let result = canonicalize_descriptor(&descriptor, &mut sources).expect("cue identity");
        assert_eq!(result.platform(), expected_platform);
        assert_eq!(result.content_type(), expected_type);
    }
}

#[test]
fn gdi_requires_high_density_and_structural_dreamcast_ip_data() {
    let descriptor = parse_gdi("2\n1 0 4 2048 \"low.bin\" 0\n2 45000 4 2048 \"high.bin\" 0\n")
        .expect("gdi descriptor");
    let mut low = MemoryReader::new(vec![0_u8; ISO_SECTOR_BYTES]);
    let mut high = MemoryReader::new(build_dreamcast_iso());
    let mut sources = [
        OpticalSource::new("low.bin", &mut low),
        OpticalSource::new("high.bin", &mut high),
    ];
    let result = canonicalize_descriptor(&OpticalDescriptor::Gdi(descriptor), &mut sources)
        .expect("gdi identity");
    assert_eq!(
        result.platform(),
        argus_application::PlatformId::SegaDreamcast
    );
    assert_eq!(
        result.content_type(),
        argus_application::ContentType::OpticalDiscGd
    );
    assert_eq!(result.source_representation(), "gdi");
}

#[test]
fn native_iso_requires_filesystem_and_playstation_boot_contract() {
    let mut reader = MemoryReader::new(build_ps1_iso());
    let result = recognize_native_optical(&mut reader).expect("iso identity");
    assert_eq!(
        result.platform(),
        argus_application::PlatformId::SonyPlaystation
    );
    assert_eq!(
        result.content_type(),
        argus_application::ContentType::OpticalDiscCd
    );
    assert_eq!(result.source_representation(), "iso-2048-cd");
}

#[test]
fn native_iso_structurally_distinguishes_ps2_cd() {
    let mut reader = MemoryReader::new(build_ps2_iso());
    let result = recognize_native_optical(&mut reader).expect("ps2 identity");
    assert_eq!(
        result.platform(),
        argus_application::PlatformId::SonyPlaystation2
    );
    assert_eq!(
        result.content_type(),
        argus_application::ContentType::OpticalDiscCd
    );
}

#[test]
fn native_iso_requires_psp_metadata_and_boot_file() {
    let mut reader = MemoryReader::new(build_psp_iso());
    let result = recognize_native_optical(&mut reader).expect("psp identity");
    assert_eq!(result.platform(), argus_application::PlatformId::SonyPsp);
    assert_eq!(
        result.content_type(),
        argus_application::ContentType::OpticalDiscUmd
    );
}

#[test]
fn arbitrary_platform_strings_in_iso_files_are_not_authority() {
    for marker in [
        b"SEGADISCSYSTEM".as_slice(),
        b"SEGA SEGASATURN ".as_slice(),
        b"SEGA SEGAKATANA ".as_slice(),
    ] {
        let image = build_iso_with_files(vec![("README.TXT;1".to_owned(), marker.to_vec())]);
        let mut reader = MemoryReader::new(image);
        assert!(recognize_native_optical(&mut reader).is_err());
    }
}

#[test]
fn generic_iso_boot2_text_in_unrelated_file_is_not_ps2() {
    let image = build_iso_with_files(vec![(
        "README.TXT;1".to_owned(),
        b"BOOT2 is mentioned here".to_vec(),
    )]);
    let mut reader = MemoryReader::new(image);
    assert!(recognize_native_optical(&mut reader).is_err());
}

#[test]
fn generic_iso_psx_exe_bytes_without_boot_contract_are_not_ps1() {
    let image = build_iso_with_files(vec![(
        "README.TXT;1".to_owned(),
        b"SYSTEM.CNF PS-X EXE is documentation, not a boot contract".to_vec(),
    )]);
    let mut reader = MemoryReader::new(image);
    assert!(recognize_native_optical(&mut reader).is_err());
}

#[test]
fn generic_iso_psp_marker_text_without_metadata_is_not_psp() {
    let image = build_iso_with_files(vec![(
        "README.TXT;1".to_owned(),
        b"PSP-UMD UMD GAME".to_vec(),
    )]);
    let mut reader = MemoryReader::new(image);
    assert!(recognize_native_optical(&mut reader).is_err());
}

#[test]
fn malformed_gamecube_and_wii_geometry_is_rejected_even_with_magic() {
    let mut gamecube = vec![0_u8; 0x8000];
    gamecube[0x1c..0x20].copy_from_slice(&[0xc2, 0x33, 0x9f, 0x3d]);
    let mut gamecube_reader = MemoryReader::new(gamecube);
    assert!(recognize_native_optical(&mut gamecube_reader).is_err());

    let mut wii = vec![0_u8; 0x8000];
    wii[0x18..0x1c].copy_from_slice(&[0x5d, 0x1c, 0x9e, 0xa3]);
    let mut wii_reader = MemoryReader::new(wii);
    assert!(recognize_native_optical(&mut wii_reader).is_err());
}

#[test]
fn valid_gamecube_and_wii_require_filesystem_and_partition_structures() {
    let mut gamecube_reader = MemoryReader::new(build_valid_gamecube_image());
    let gamecube = recognize_native_optical(&mut gamecube_reader).expect("GameCube");
    assert_eq!(
        gamecube.platform(),
        argus_application::PlatformId::NintendoGameCube
    );
    assert_eq!(
        gamecube.content_type(),
        argus_application::ContentType::OpticalDiscGameCube
    );

    let mut wii_reader = MemoryReader::new(build_valid_wii_image());
    let wii = recognize_native_optical(&mut wii_reader).expect("Wii");
    assert_eq!(wii.platform(), argus_application::PlatformId::NintendoWii);
    assert_eq!(
        wii.content_type(),
        argus_application::ContentType::OpticalDiscWii
    );
}

#[test]
fn optical_processing_is_cancellable_and_playlist_limits_are_bounded() {
    let mut raw = vec![0_u8; 0x8000];
    raw[0x18..0x1c].copy_from_slice(&[0x5d, 0x1c, 0x9e, 0xa3]);
    let mut reader = MemoryReader::new(raw);
    assert_eq!(
        recognize_native_optical_with_cancel(&mut reader, &|| true),
        Err(OpticalError::Cancelled)
    );
    assert_eq!(
        parse_m3u(&vec![b'x'; 1024 * 1024 + 1]),
        Err(argus_infrastructure::content::M3uError::ResourceLimitExceeded)
    );
}

#[test]
fn descriptor_rejects_traversal_and_missing_or_duplicate_sources() {
    assert_eq!(
        parse_descriptor(b"FILE \"../disc.bin\" BINARY\nTRACK 01 MODE1/2048\nINDEX 01 00:00:00\n"),
        Err(OpticalError::Traversal)
    );
    let descriptor =
        parse_cue("FILE \"disc.bin\" BINARY\nTRACK 01 MODE1/2048\nINDEX 01 00:00:00\n")
            .expect("cue descriptor");
    let mut reader = MemoryReader::new(build_sega_cd_iso(b"SEGADISCSYSTEM"));
    let mut missing = [OpticalSource::new("other.bin", &mut reader)];
    assert_eq!(
        canonicalize_descriptor(&OpticalDescriptor::Cue(descriptor.clone()), &mut missing),
        Err(OpticalError::MissingDependency)
    );
    let mut first = MemoryReader::new(build_sega_cd_iso(b"SEGADISCSYSTEM"));
    let mut second = MemoryReader::new(build_sega_cd_iso(b"SEGADISCSYSTEM"));
    let mut duplicate = [
        OpticalSource::new("disc.bin", &mut first),
        OpticalSource::new("disc.bin", &mut second),
    ];
    assert_eq!(
        canonicalize_descriptor(&OpticalDescriptor::Cue(descriptor), &mut duplicate),
        Err(OpticalError::MissingDependency)
    );
}

#[test]
fn m3u_preserves_order_and_is_relationship_evidence_only() {
    let playlist =
        parse_m3u(b"#EXTM3U\n#EXTINF:-1,Disc 1\ndisc-1.cue\n#EXTINF:-1,Disc 2\ndisc-2.cue\n")
            .expect("playlist");
    assert_eq!(
        playlist.members(),
        &["disc-1.cue".to_owned(), "disc-2.cue".to_owned()]
    );
}
