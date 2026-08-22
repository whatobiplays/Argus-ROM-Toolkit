package com.argusromtoolkit.argus

import java.io.File

/**
 * Stable backend/platform-relative diagnostics artifact contract.
 *
 * Rust owns creation, sanitization, ZIP completion, and archive validity. This
 * object only lets Android locate the one completed artifact that it may
 * publish. It deliberately performs no ZIP parsing.
 */
internal object ArgusDiagnosticsPublicationContract {
    const val RELATIVE_ARTIFACT_PATH = "diagnostics/startup-diagnostics-v1.zip"
    const val MAX_ARTIFACT_BYTES = 10L * 1024L * 1024L

    fun resolveCompletedArtifact(applicationDataDirectory: File): File? {
        return try {
            val publicationDirectory = File(applicationDataDirectory, "diagnostics")
            val expectedArtifact = File(applicationDataDirectory, RELATIVE_ARTIFACT_PATH)
            val canonicalDirectory = publicationDirectory.canonicalFile
            val canonicalArtifact = expectedArtifact.canonicalFile
            if (!isConfinedToPublicationDirectory(canonicalDirectory, canonicalArtifact)) {
                return null
            }
            if (!canonicalArtifact.exists() || !canonicalArtifact.isFile) {
                return null
            }
            if (canonicalArtifact.length() !in 1L..MAX_ARTIFACT_BYTES) {
                return null
            }
            canonicalArtifact
        } catch (_: java.io.IOException) {
            null
        }
    }

    fun isConfinedToPublicationDirectory(
        publicationDirectory: File,
        candidate: File,
    ): Boolean {
        val directoryPath = publicationDirectory.canonicalFile.path
        val candidatePath = candidate.canonicalFile.path
        return candidatePath != directoryPath &&
            candidatePath.startsWith("$directoryPath${File.separator}")
    }
}
