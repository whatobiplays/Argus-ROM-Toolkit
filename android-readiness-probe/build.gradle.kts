plugins { id("com.android.application") version "9.0.1" }
android {
    namespace = "com.argusromtoolkit.argus.readinessprobe"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.argusromtoolkit.argus.readinessprobe"
        minSdk = 30
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }
    buildTypes { create("probe") { isDebuggable = false; signingConfig = null } }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    testOptions { unitTests.isIncludeAndroidResources = true }
}
androidComponents { beforeVariants { it.enable = it.buildType == "probe"; it.hostTests["UnitTest"]?.enable = it.buildType == "probe" } }
dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16.1")
}

// The caller pins the reviewed source commit; signing happens outside this build.
val sourceCommit = providers.gradleProperty("probeSourceCommit").orElse(
    providers.exec { commandLine("git", "rev-parse", "HEAD") }.standardOutput.asText.map { it.trim() }
)
val buildRecordDirectory = layout.buildDirectory.dir("generated/probeAssets")
val generateProbeBuildRecord by tasks.registering {
    inputs.property("sourceCommit", sourceCommit)
    outputs.dir(buildRecordDirectory)
    doLast {
        val commit = sourceCommit.get()
        require(commit.matches(Regex("[0-9a-f]{40}")))
        buildRecordDirectory.get().asFile.apply { mkdirs() }
            .resolve("readiness-probe-build.json")
            .writeText("""{"source_commit":"$commit","variant":"probe"}""")
    }
}
android.sourceSets.getByName("main").assets.srcDir(buildRecordDirectory.get().asFile)
tasks.named("preBuild").configure { dependsOn(generateProbeBuildRecord) }
