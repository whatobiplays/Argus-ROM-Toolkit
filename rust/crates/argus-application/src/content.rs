//! Application-owned transformation and identity catalogs.

use argus_domain::{ContentType, PlatformId};

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
    platform: PlatformId,
    content_type: ContentType,
}

impl TransformationDescriptor {
    /// Creates one stable production descriptor.
    pub const fn new(id: &'static str, platform: PlatformId, content_type: ContentType) -> Self {
        Self {
            id,
            platform,
            content_type,
        }
    }

    /// Returns the stable transformation identifier.
    pub const fn id(&self) -> &'static str {
        self.id
    }

    /// Returns the validated output platform.
    pub const fn platform(&self) -> PlatformId {
        self.platform
    }

    /// Returns the validated output content type.
    pub const fn content_type(&self) -> ContentType {
        self.content_type
    }
}

/// Registry of transformation mechanisms, intentionally separate from the
/// identity schemes that consume their typed output.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TransformationRegistry {
    descriptors: Vec<TransformationDescriptor>,
}

impl TransformationRegistry {
    /// Returns the initially active raw-cartridge transformation tranche.
    pub fn production() -> Self {
        Self {
            descriptors: vec![
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-gb.raw-cartridge.v1",
                    PlatformId::NintendoGb,
                    ContentType::CartridgeImage,
                ),
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-gbc.raw-cartridge.v1",
                    PlatformId::NintendoGbc,
                    ContentType::CartridgeImage,
                ),
                TransformationDescriptor::new(
                    "argus.transformation.nintendo-gba.raw-cartridge.v1",
                    PlatformId::NintendoGba,
                    ContentType::CartridgeImage,
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
}

/// One current BE-014 identity-scheme descriptor.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct IdentitySchemeDescriptor {
    id: &'static str,
    platform: PlatformId,
    content_type: ContentType,
    revision: u32,
    algorithm: &'static str,
    representation: &'static str,
}

impl IdentitySchemeDescriptor {
    const fn new(id: &'static str, platform: PlatformId, content_type: ContentType) -> Self {
        Self {
            id,
            platform,
            content_type,
            revision: 1,
            algorithm: "sha256",
            representation: "raw-cartridge-image",
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

    /// Returns the accepted source representation.
    pub const fn representation(&self) -> &'static str {
        self.representation
    }

    /// Applies this catalog policy to a validated typed transformation result.
    pub fn identity(&self, digest: IdentityDigest) -> crate::ContentIdentity {
        crate::ContentIdentity::new(self.id, self.revision, digest)
    }
}

/// Production identity catalog activated for this slice.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct IdentitySchemeCatalog {
    descriptors: Vec<IdentitySchemeDescriptor>,
}

impl IdentitySchemeCatalog {
    /// Returns exactly the three approved production schemes.
    pub fn production() -> Self {
        Self {
            descriptors: vec![
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.nintendo-gb.cartridge.v1",
                    PlatformId::NintendoGb,
                    ContentType::CartridgeImage,
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.nintendo-gbc.cartridge.v1",
                    PlatformId::NintendoGbc,
                    ContentType::CartridgeImage,
                ),
                IdentitySchemeDescriptor::new(
                    "argus.content.identity.nintendo-gba.cartridge.v1",
                    PlatformId::NintendoGba,
                    ContentType::CartridgeImage,
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
        digest: IdentityDigest,
    ) -> Option<crate::ContentIdentity> {
        self.select(platform, content_type)
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
