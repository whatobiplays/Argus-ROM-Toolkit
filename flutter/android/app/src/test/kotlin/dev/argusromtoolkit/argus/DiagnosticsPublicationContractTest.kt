package dev.argusromtoolkit.argus

import java.io.File
import java.io.RandomAccessFile
import kotlin.io.path.createTempDirectory
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DiagnosticsPublicationContractTest {
    @Test
    fun resolvesOnlyTheExpectedBoundedRegularArtifact() {
        val root = createTempDirectory("argus-diagnostics").toFile()
        val artifact = File(
            root,
            ArgusDiagnosticsPublicationContract.RELATIVE_ARTIFACT_PATH,
        )
        checkNotNull(artifact.parentFile).mkdirs()
        artifact.writeBytes(byteArrayOf(1, 2, 3))

        val resolved = ArgusDiagnosticsPublicationContract.resolveCompletedArtifact(root)

        assertNotNull(resolved)
        assertTrue(resolved!!.canonicalFile == artifact.canonicalFile)
    }

    @Test
    fun rejectsMissingNonRegularAndOversizedArtifacts() {
        val root = createTempDirectory("argus-diagnostics").toFile()

        assertNull(ArgusDiagnosticsPublicationContract.resolveCompletedArtifact(root))

        val artifact = File(
            root,
            ArgusDiagnosticsPublicationContract.RELATIVE_ARTIFACT_PATH,
        )
        checkNotNull(artifact.parentFile).mkdirs()
        artifact.mkdir()
        assertNull(ArgusDiagnosticsPublicationContract.resolveCompletedArtifact(root))

        artifact.delete()
        artifact.createNewFile()
        RandomAccessFile(artifact, "rw").use { output ->
            output.setLength(
                ArgusDiagnosticsPublicationContract.MAX_ARTIFACT_BYTES + 1,
            )
        }
        assertNull(ArgusDiagnosticsPublicationContract.resolveCompletedArtifact(root))
    }

    @Test
    fun rejectsPathTraversalOutsideTheDiagnosticPublicationDirectory() {
        val root = createTempDirectory("argus-diagnostics").toFile()
        val publicationDirectory = File(root, "diagnostics")
        val outside = File(root, "outside.zip")

        assertFalse(
            ArgusDiagnosticsPublicationContract.isConfinedToPublicationDirectory(
                publicationDirectory,
                outside,
            ),
        )
        assertFalse(
            ArgusDiagnosticsPublicationContract.isConfinedToPublicationDirectory(
                publicationDirectory,
                File(publicationDirectory, "../outside.zip"),
            ),
        )
    }
}
