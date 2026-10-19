import java.io.File

// All generated native and qualification inputs live under the Flutter build
// directory. Keeping them out of src/main avoids stale developer outputs being
// packaged into an unrelated variant.
val repositoryRoot = rootProject.projectDir.parentFile.parentFile
val flutterBuildDirectory = rootProject.layout.buildDirectory.get().asFile
val debugJniDirectory = File(flutterBuildDirectory, "native-jni/debug")
val releaseJniDirectory = File(flutterBuildDirectory, "native-jni/release")
val qualificationBuildAssetsDirectory =
    File(flutterBuildDirectory, "generated/qualification-assets")
val qualificationBuildRecord =
    File(qualificationBuildAssetsDirectory, "qualification-build.json")
val qualificationPrebuildSource =
    File(flutterBuildDirectory, "qualification/prebuild-source.json")

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.argusromtoolkit.argus"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.argusromtoolkit.argus"
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = providers.environmentVariable("ARGUS_RELEASE_KEYSTORE")
                .map { File(it) }
                .orNull
            storePassword =
                providers.environmentVariable("ARGUS_RELEASE_STORE_PASSWORD").orNull
            keyAlias = providers.environmentVariable("ARGUS_RELEASE_KEY_ALIAS").orNull
            keyPassword =
                providers.environmentVariable("ARGUS_RELEASE_KEY_PASSWORD").orNull
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }

        // The qualification artifact is a Release build in every functional
        // sense (non-debuggable, AOT, optimized Rust) but has a separate
        // install identity and uses the ordinary Android debug signing key.
        // It never shares a signing configuration with the distributable
        // Release variant.
        create("qualification") {
            initWith(getByName("release"))
            applicationIdSuffix = ".qualification"
            signingConfig = signingConfigs.getByName("debug")
            isDebuggable = false
            isJniDebuggable = false
            // Flutter plugin AARs publish debug, profile, and release only.
            // The qualification variant therefore consumes each dependency's
            // release variant instead of relying on an implicit fallback.
            matchingFallbacks.add("release")
        }
    }

    sourceSets {
        // The former src/main/jniLibs location is intentionally excluded. A
        // stale local build there must not contaminate Debug, Release, or
        // Qualification, and excluding it removes duplicate JNI entries.
        getByName("main").jniLibs.setSrcDirs(emptyList<File>())
        getByName("debug").jniLibs.srcDir(debugJniDirectory)
        getByName("release").jniLibs.srcDir(releaseJniDirectory)
        maybeCreate("qualification").jniLibs.srcDir(releaseJniDirectory)
        maybeCreate("qualification").assets.srcDir(qualificationBuildAssetsDirectory)
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// The generated Gradle build remains the Android packaging owner; these
// tasks only produce the ABI-specific Argus Rust bridge libraries. Debug and
// Release use separate Cargo profiles and separate output directories.
// Android SDK/NDK remain explicit native-build prerequisites and are never
// required by the platform-neutral `just check` gate.
val buildAndroidBridgeDebug by tasks.registering(Exec::class) {
    group = "build"
    description = "Build the Debug-profile ARM64 Argus native bridge libraries."
    workingDir(repositoryRoot)
    commandLine(
        "bash",
        File(repositoryRoot, "scripts/build_android_bridge.sh").absolutePath,
        "--debug",
        "--output-dir",
        debugJniDirectory.absolutePath,
    )
    inputs.file(File(repositoryRoot, "scripts/build_android_bridge.sh"))
    inputs.files(
        fileTree(File(repositoryRoot, "rust")) {
            include("**/*.rs", "**/Cargo.toml", "Cargo.lock")
        },
    )
    outputs.dir(debugJniDirectory)
    // Native metadata contains Git revision and dirty state outside the Rust
    // source inputs. Always rerunning prevents an UP-TO-DATE task from
    // retaining metadata for a different source snapshot.
    outputs.upToDateWhen { false }
}

val buildAndroidBridgeRelease by tasks.registering(Exec::class) {
    group = "build"
    description = "Build the Release-profile ARM64 Argus native bridge libraries."
    workingDir(repositoryRoot)
    commandLine(
        "bash",
        File(repositoryRoot, "scripts/build_android_bridge.sh").absolutePath,
        "--release",
        "--output-dir",
        releaseJniDirectory.absolutePath,
    )
    inputs.file(File(repositoryRoot, "scripts/build_android_bridge.sh"))
    inputs.files(
        fileTree(File(repositoryRoot, "rust")) {
            include("**/*.rs", "**/Cargo.toml", "Cargo.lock")
        },
    )
    outputs.dir(releaseJniDirectory)
    // See the Debug task: Git provenance must be regenerated for every build.
    outputs.upToDateWhen { false }
}

// The embedded record binds the APK to the exact Git revision and deterministic
// source fingerprint that produced it. Running it fresh on every build avoids
// a configuration-cache hit silently reusing an older source record.
val generateQualificationBuildInfo by tasks.registering(Exec::class) {
    group = "build"
    description = "Record the qualification APK source and build-mode identity."
    workingDir(repositoryRoot)
    environment("PYTHONPATH", repositoryRoot.absolutePath)
    environment("PYTHONDONTWRITEBYTECODE", "1")
    commandLine(
        "python3",
        "-m",
        "scripts.android_qualification.packaging",
        "build-record",
        "--root",
        repositoryRoot.absolutePath,
        "--output",
        qualificationBuildRecord.absolutePath,
        "--prebuild-source-state",
        qualificationPrebuildSource.absolutePath,
    )
    outputs.dir(qualificationBuildAssetsDirectory)
    outputs.upToDateWhen { false }
}

// Capture the operator's pre-build source snapshot before either AOT or native
// compilation can start. The qualification shell entrypoint writes the snapshot
// before invoking Gradle; the record task compares that snapshot with its own
// observation, and final verification compares both with the worktree. The
// native task does not depend on the record task because it is shared with the
// ordinary Release build, which has no qualification assets to generate.
tasks.matching { it.name == "compileFlutterBuildQualification" }.configureEach {
    dependsOn(generateQualificationBuildInfo)
}

// Be explicit about the variant tasks that consume each native directory.
// preBuild ordering alone does not establish that Gradle generated the JNI
// inputs before the merger or packager ran.
mapOf(
    "Debug" to buildAndroidBridgeDebug,
    "Release" to buildAndroidBridgeRelease,
    "Qualification" to buildAndroidBridgeRelease,
).forEach { (variant, nativeTask) ->
    tasks.matching {
        it.name == "merge${variant}JniLibFolders" || it.name == "package${variant}"
    }.configureEach {
        dependsOn(nativeTask)
    }
}

tasks.matching {
    it.name == "mergeQualificationAssets" || it.name == "packageQualification"
}.configureEach {
    dependsOn(generateQualificationBuildInfo)
}

// Distributable Release signing is external and mandatory. Only the ordinary
// Release packaging/signing tasks are guarded; the qualification variant and
// its Release-profile native task intentionally do not require these values.
// A guarded task with missing or unreadable signing configuration fails
// explicitly and never falls back to the debug key.
tasks.matching {
    it.name.startsWith("packageRelease") ||
        it.name.startsWith("bundleRelease") ||
        it.name.startsWith("signRelease") ||
        it.name.startsWith("validateSigningRelease")
}.configureEach {
    doFirst {
        val missingFields = mutableListOf<String>()
        for (name in listOf(
            "ARGUS_RELEASE_KEYSTORE",
            "ARGUS_RELEASE_STORE_PASSWORD",
            "ARGUS_RELEASE_KEY_ALIAS",
            "ARGUS_RELEASE_KEY_PASSWORD",
        )) {
            if (providers.environmentVariable(name).orNull.isNullOrBlank()) {
                missingFields.add(name)
            }
        }
        val keystore = providers.environmentVariable("ARGUS_RELEASE_KEYSTORE").orNull
        if (missingFields.none { it == "ARGUS_RELEASE_KEYSTORE" } &&
            keystore != null
        ) {
            if (!File(keystore).isAbsolute) {
                missingFields.add("ARGUS_RELEASE_KEYSTORE (must be absolute)")
            } else if (!File(keystore).isFile) {
                missingFields.add("ARGUS_RELEASE_KEYSTORE (file not found)")
            }
        }
        if (missingFields.isNotEmpty()) {
            throw GradleException(
                "Release signing configuration is incomplete: " +
                    missingFields.joinToString(", "),
            )
        }
    }
}
