//! Application-owned transformation and identity catalogs.

use argus_domain::{ContentType, PlatformId};

use crate::TransformationOutput;

/// Fixed-width SHA-256 identity value carried across application ports.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub struct IdentityDigest([u8; 32]);

impl IdentityDigest {
    /// Wraps one complete SHA-256 digest.
    pub const fn from_bytes(bytes: [u8; 32]) -> Self {
        Self(bytes)
    }

    /// Returns the exact digest bytes.
    pub const fn as_bytes(self) -> [u8; 32] {
        self.0
    }
}

/// Stable descriptor for a mechanism that produces a validated typed result.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TransformationDescriptor {
    id: &'static str,
    revision: u32,
    representation: &'static str,
    output: TransformationOutput,
}

impl TransformationDescriptor {
    /// Creates one stable production descriptor.
    pub const fn new(
        id: &'static str,
        platform: PlatformId,
        content_type: ContentType,
        representation: &'static str,
    ) -> Self {
        Self {
            id,
            revision: 1,
            representation,
            output: TransformationOutput::TypedContent {
                platform,
                content_type,
            },
        }
    }

    /// Creates a stable descriptor for a derived source scope.
    pub const fn new_derived(id: &'static str, representation: &'static str) -> Self {
        Self {
            id,
            revision: 1,
            representation,
            output: TransformationOutput::DerivedScope,
        }
    }

    /// Returns the stable transformation identifier.
    pub const fn id(&self) -> &'static str {
        self.id
    }

    /// Returns the trusted implementation revision.
    pub const fn revision(&self) -> u32 {
        self.revision
    }

    /// Returns the transformation output category.
    pub const fn output(&self) -> TransformationOutput {
        self.output
    }

    /// Returns the source representation consumed by this transformation.
    pub const fn representation(&self) -> &'static str {
        self.representation
    }

    /// Returns the typed output platform when this is a typed transformation.
    pub const fn platform(&self) -> Option<PlatformId> {
        match self.output {
            TransformationOutput::DerivedScope => None,
            TransformationOutput::TypedContent { platform, .. } => Some(platform),
        }
    }

    /// Returns the typed output content class when this is a typed transformation.
    pub const fn content_type(&self) -> Option<ContentType> {
        match self.output {
            TransformationOutput::DerivedScope => None,
            TransformationOutput::TypedContent { content_type, .. } => Some(content_type),
        }
    }
}

/// Registry of transformation mechanisms, intentionally separate from the
/// identity schemes that consume their typed output.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TransformationRegistry {
    descriptors: Vec<TransformationDescriptor>,
}

impl TransformationRegistry {
    /// Returns the active transformation mechanisms in stable order.
    pub fn production() -> Self {
        Self {
            descriptors: vec![
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-gb.raw-cartridge.v1",
                    PlatformId::NintendoGb,
                    ContentType::CartridgeImage,
                    "raw-cartridge-image",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-gbc.raw-cartridge.v1",
                    PlatformId::NintendoGbc,
                    ContentType::CartridgeImage,
                    "raw-cartridge-image",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-gba.raw-cartridge.v1",
                    PlatformId::NintendoGba,
                    ContentType::CartridgeImage,
                    "raw-cartridge-image",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-nes.nes-2.v1",
                    PlatformId::NintendoNes,
                    ContentType::CartridgeImage,
                    "nes-2",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-nes.nes-ines.v1",
                    PlatformId::NintendoNes,
                    ContentType::CartridgeImage,
                    "nes-ines",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-fds.fds-fw.v1",
                    PlatformId::NintendoFds,
                    ContentType::MagneticDiskImage,
                    "fds-fw",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-fds.fds-headerless.v1",
                    PlatformId::NintendoFds,
                    ContentType::MagneticDiskImage,
                    "fds-headerless",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-snes.snes-linear.v1",
                    PlatformId::NintendoSnes,
                    ContentType::CartridgeImage,
                    "snes-linear",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-snes.snes-copier-headered.v1",
                    PlatformId::NintendoSnes,
                    ContentType::CartridgeImage,
                    "snes-copier-headered",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-n64.n64-native.v1",
                    PlatformId::NintendoN64,
                    ContentType::CartridgeImage,
                    "n64-native",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-n64.n64-byteswapped16.v1",
                    PlatformId::NintendoN64,
                    ContentType::CartridgeImage,
                    "n64-byteswapped16",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-n64.n64-byteswapped32.v1",
                    PlatformId::NintendoN64,
                    ContentType::CartridgeImage,
                    "n64-byteswapped32",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-nds.raw-cartridge.v1",
                    PlatformId::NintendoNds,
                    ContentType::CartridgeImage,
                    "raw-cartridge-image",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-3ds.ncsd-nocrypto.v1",
                    PlatformId::Nintendo3ds,
                    ContentType::CartridgeImage,
                    "ncsd-nocrypto",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sega-sms.raw-cartridge.v1",
                    PlatformId::SegaSms,
                    ContentType::CartridgeImage,
                    "raw-cartridge-image",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sega-gamegear.raw-cartridge.v1",
                    PlatformId::SegaGameGear,
                    ContentType::CartridgeImage,
                    "raw-cartridge-image",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sega-genesis.genesis-linear-be.v1",
                    PlatformId::SegaGenesis,
                    ContentType::CartridgeImage,
                    "genesis-linear-be",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sega-genesis.genesis-smd.v1",
                    PlatformId::SegaGenesis,
                    ContentType::CartridgeImage,
                    "genesis-smd",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sega-32x.genesis-linear-be.v1",
                    PlatformId::Sega32x,
                    ContentType::CartridgeImage,
                    "genesis-linear-be",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sega-cd.cue-bin.v1",
                    PlatformId::SegaCd,
                    ContentType::OpticalDiscCd,
                    "cue-bin",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sega-cd.iso-2048-cd.v1",
                    PlatformId::SegaCd,
                    ContentType::OpticalDiscCd,
                    "iso-2048-cd",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sega-saturn.cue-bin.v1",
                    PlatformId::SegaSaturn,
                    ContentType::OpticalDiscCd,
                    "cue-bin",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sega-saturn.iso-2048-cd.v1",
                    PlatformId::SegaSaturn,
                    ContentType::OpticalDiscCd,
                    "iso-2048-cd",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sega-dreamcast.gdi.v1",
                    PlatformId::SegaDreamcast,
                    ContentType::OpticalDiscGd,
                    "gdi",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sega-dreamcast.cue-bin.v1",
                    PlatformId::SegaDreamcast,
                    ContentType::OpticalDiscGd,
                    "cue-bin",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sony-playstation.cue-bin.v1",
                    PlatformId::SonyPlaystation,
                    ContentType::OpticalDiscCd,
                    "cue-bin",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sony-playstation.iso-2048-cd.v1",
                    PlatformId::SonyPlaystation,
                    ContentType::OpticalDiscCd,
                    "iso-2048-cd",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sony-playstation2.cd-cue-bin.v1",
                    PlatformId::SonyPlaystation2,
                    ContentType::OpticalDiscCd,
                    "cue-bin",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sony-playstation2.cd-iso-2048.v1",
                    PlatformId::SonyPlaystation2,
                    ContentType::OpticalDiscCd,
                    "iso-2048-cd",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sony-playstation2.dvd-iso-2048.v1",
                    PlatformId::SonyPlaystation2,
                    ContentType::OpticalDiscDvd,
                    "iso-2048",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sony-psp.umd-iso-2048.v1",
                    PlatformId::SonyPsp,
                    ContentType::OpticalDiscUmd,
                    "iso-2048",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-gamecube.raw-disc.v1",
                    PlatformId::NintendoGameCube,
                    ContentType::OpticalDiscGameCube,
                    "raw-disc-image",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-wii.raw-disc.v1",
                    PlatformId::NintendoWii,
                    ContentType::OpticalDiscWii,
                    "raw-disc-image",
                ),
                TransformationDescriptor::new_derived("argus.transformation.zip.v1", "zip"),
                TransformationDescriptor::new_derived(
                    "argus.transformation.sevenzip.v1",
                    "sevenzip",
                ),
                TransformationDescriptor::new_derived("argus.transformation.tar.v1", "tar"),
                TransformationDescriptor::new_derived("argus.transformation.gzip.v1", "gzip"),
                TransformationDescriptor::new_derived("argus.transformation.bzip2.v1", "bzip2"),
                TransformationDescriptor::new_derived("argus.transformation.xz.v1", "xz"),
                TransformationDescriptor::new(
                    "argus.transformation.sega-cd.chd-cd.v1",
                    PlatformId::SegaCd,
                    ContentType::OpticalDiscCd,
                    "chd-cd",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sega-saturn.chd-cd.v1",
                    PlatformId::SegaSaturn,
                    ContentType::OpticalDiscCd,
                    "chd-cd",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sony-playstation.chd-cd.v1",
                    PlatformId::SonyPlaystation,
                    ContentType::OpticalDiscCd,
                    "chd-cd",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sony-playstation2-cd.chd-cd.v1",
                    PlatformId::SonyPlaystation2,
                    ContentType::OpticalDiscCd,
                    "chd-cd",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sega-dreamcast.chd-gd.v1",
                    PlatformId::SegaDreamcast,
                    ContentType::OpticalDiscGd,
                    "chd-gd",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sony-playstation2-dvd.chd-dvd.v1",
                    PlatformId::SonyPlaystation2,
                    ContentType::OpticalDiscDvd,
                    "chd-dvd",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sony-psp.chd-umd.v1",
                    PlatformId::SonyPsp,
                    ContentType::OpticalDiscUmd,
                    "chd-umd",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-gamecube.rvz.v1",
                    PlatformId::NintendoGameCube,
                    ContentType::OpticalDiscGameCube,
                    "rvz",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-wii.rvz.v1",
                    PlatformId::NintendoWii,
                    ContentType::OpticalDiscWii,
                    "rvz",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.sony-psp.cso.v1",
                    PlatformId::SonyPsp,
                    ContentType::OpticalDiscUmd,
                    "cso",
                ),
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-wii.wbfs.v1",
                    PlatformId::NintendoWii,
                    ContentType::OpticalDiscWii,
                    "wbfs",
                ),
            ],
        }
    }

    /// Returns registered descriptors in stable order.
    pub fn descriptors(&self) -> &[TransformationDescriptor] {
        &self.descriptors
    }

    /// Returns the number of registered mechanisms.
    pub fn len(&self) -> usize {
        self.descriptors.len()
    }

    /// Returns whether no transformation mechanisms are registered.
    pub fn is_empty(&self) -> bool {
        self.descriptors.is_empty()
    }

    /// Returns whether one representation is registered for production use.
    pub fn supports(&self, representation: &str) -> bool {
        self.descriptors
            .iter()
            .any(|descriptor| descriptor.representation() == representation)
    }
}

/// One current BE-014 identity-scheme descriptor.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct IdentitySchemeDescriptor {
    id: &'static str,
    platform: PlatformId,
    content_type: ContentType,
    revision: u32,
    algorithm: &'static str,
    representations: &'static [&'static str],
}

impl IdentitySchemeDescriptor {
    const fn new(
        id: &'static str,
        platform: PlatformId,
        content_type: ContentType,
        representations: &'static [&'static str],
    ) -> Self {
        Self {
            id,
            platform,
            content_type,
            revision: 1,
            algorithm: "sha256",
            representations,
        }
    }

    /// Returns the stable scheme identifier.
    pub const fn id(&self) -> &'static str {
        self.id
    }

    /// Returns the scheme platform.
    pub const fn platform(&self) -> PlatformId {
        self.platform
    }

    /// Returns the scheme content type.
    pub const fn content_type(&self) -> ContentType {
        self.content_type
    }

    /// Returns the identity revision.
    pub const fn revision(&self) -> u32 {
        self.revision
    }

    /// Returns the digest algorithm identifier.
    pub const fn algorithm(&self) -> &'static str {
        self.algorithm
    }

    /// Returns all accepted source representations in stable order.
    pub const fn representations(&self) -> &'static [&'static str] {
        self.representations
    }

    /// Returns the first accepted source representation for legacy callers.
    pub const fn representation(&self) -> &'static str {
        self.representations[0]
    }

    /// Returns whether the catalog authorizes one source representation.
    pub fn accepts_representation(&self, representation: &str) -> bool {
        self.representations.contains(&representation)
    }

    /// Applies this catalog policy to a validated typed transformation result.
    pub fn identity(&self, digest: IdentityDigest) -> crate::ContentIdentity {
        crate::ContentIdentity::new(self.id, self.revision, digest)
    }
}

/// Production identity catalog for supported content identities.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct IdentitySchemeCatalog {
    descriptors: Vec<IdentitySchemeDescriptor>,
}

impl IdentitySchemeCatalog {
    /// Returns the approved production schemes for cartridge and native/raw
    /// optical content.
    pub fn production() -> Self {
        Self {
            descriptors: vec![
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.nintendo-nes.cartridge.v1",
                    PlatformId::NintendoNes,
                    ContentType::CartridgeImage,
                    &["nes-2", "nes-ines"],
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.nintendo-fds.disk.v1",
                    PlatformId::NintendoFds,
                    ContentType::MagneticDiskImage,
                    &["fds-fw", "fds-headerless"],
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.nintendo-snes.cartridge.v1",
                    PlatformId::NintendoSnes,
                    ContentType::CartridgeImage,
                    &["snes-linear", "snes-copier-headered"],
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.nintendo-gb.cartridge.v1",
                    PlatformId::NintendoGb,
                    ContentType::CartridgeImage,
                    &["raw-cartridge-image"],
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.nintendo-gbc.cartridge.v1",
                    PlatformId::NintendoGbc,
                    ContentType::CartridgeImage,
                    &["raw-cartridge-image"],
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.nintendo-gba.cartridge.v1",
                    PlatformId::NintendoGba,
                    ContentType::CartridgeImage,
                    &["raw-cartridge-image"],
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.nintendo-n64.cartridge.v1",
                    PlatformId::NintendoN64,
                    ContentType::CartridgeImage,
                    &["n64-native", "n64-byteswapped16", "n64-byteswapped32"],
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.nintendo-nds.cartridge.v1",
                    PlatformId::NintendoNds,
                    ContentType::CartridgeImage,
                    &["raw-cartridge-image"],
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.nintendo-3ds.nocrypto-ncsd.v1",
                    PlatformId::Nintendo3ds,
                    ContentType::CartridgeImage,
                    &["ncsd-nocrypto"],
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.sega-sms.cartridge.v1",
                    PlatformId::SegaSms,
                    ContentType::CartridgeImage,
                    &["raw-cartridge-image"],
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.sega-gamegear.cartridge.v1",
                    PlatformId::SegaGameGear,
                    ContentType::CartridgeImage,
                    &["raw-cartridge-image"],
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.sega-genesis.cartridge.v1",
                    PlatformId::SegaGenesis,
                    ContentType::CartridgeImage,
                    &["genesis-linear-be", "genesis-smd"],
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.sega-32x.cartridge.v1",
                    PlatformId::Sega32x,
                    ContentType::CartridgeImage,
                    &["genesis-linear-be"],
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.sega-cd.disc.v1",
                    PlatformId::SegaCd,
                    ContentType::OpticalDiscCd,
                    &["cue-bin", "iso-2048-cd", "chd-cd"],
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.sega-saturn.disc.v1",
                    PlatformId::SegaSaturn,
                    ContentType::OpticalDiscCd,
                    &["cue-bin", "iso-2048-cd", "chd-cd"],
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.sega-dreamcast.gdrom.v1",
                    PlatformId::SegaDreamcast,
                    ContentType::OpticalDiscGd,
                    &["gdi", "cue-bin", "chd-gd"],
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.sony-playstation.disc.v1",
                    PlatformId::SonyPlaystation,
                    ContentType::OpticalDiscCd,
                    &["cue-bin", "iso-2048-cd", "chd-cd"],
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.sony-playstation2.cd.v1",
                    PlatformId::SonyPlaystation2,
                    ContentType::OpticalDiscCd,
                    &["cue-bin", "iso-2048-cd", "chd-cd"],
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.sony-playstation2.dvd.v1",
                    PlatformId::SonyPlaystation2,
                    ContentType::OpticalDiscDvd,
                    &["iso-2048", "chd-dvd"],
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.sony-psp.umd.v1",
                    PlatformId::SonyPsp,
                    ContentType::OpticalDiscUmd,
                    &["iso-2048", "cso", "chd-umd"],
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.nintendo-gamecube.disc.v1",
                    PlatformId::NintendoGameCube,
                    ContentType::OpticalDiscGameCube,
                    &["raw-disc-image", "rvz"],
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.nintendo-wii.disc.v1",
                    PlatformId::NintendoWii,
                    ContentType::OpticalDiscWii,
                    &["raw-disc-image", "rvz", "wbfs"],
                ),
            ],
        }
    }

    /// Returns descriptors in stable catalog order.
    pub fn descriptors(&self) -> &[IdentitySchemeDescriptor] {
        &self.descriptors
    }

    /// Returns the unique scheme for a recognized typed representation.
    pub fn select(
        &self,
        platform: PlatformId,
        content_type: ContentType,
    ) -> Option<&IdentitySchemeDescriptor> {
        self.descriptors.iter().find(|descriptor| {
            descriptor.platform == platform && descriptor.content_type == content_type
        })
    }

    /// Maps one authoritative transformation result to exactly one active
    /// production identity scheme.
    pub fn select_identity(
        &self,
        platform: PlatformId,
        content_type: ContentType,
        representation: &str,
        digest: IdentityDigest,
    ) -> Option<crate::ContentIdentity> {
        self.select(platform, content_type)
            .filter(|descriptor| descriptor.accepts_representation(representation))
            .map(|descriptor| descriptor.identity(digest))
    }

    /// Returns the number of active schemes.
    pub fn len(&self) -> usize {
        self.descriptors.len()
    }

    /// Returns whether the production catalog has no active schemes.
    pub fn is_empty(&self) -> bool {
        self.descriptors.is_empty()
    }
}
