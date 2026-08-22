plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.io.File

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

// The generated Gradle build remains the Android packaging owner; this task
// only produces the ABI-specific Argus Rust bridge libraries that Gradle
// packages. Android SDK/NDK remain explicit native-build prerequisites and
// are never required by the platform-neutral `just check` gate.
val repositoryRoot = rootProject.projectDir.parentFile.parentFile
val buildArgusRust by tasks.registering(Exec::class) {
    workingDir(repositoryRoot)
    commandLine(
        "bash",
        File(repositoryRoot, "scripts/build_android_bridge.sh").absolutePath,
    )
}

tasks.named("preBuild") {
    dependsOn(buildArgusRust)
}

// Release signing is external and mandatory. A release task with missing or
// unreadable signing configuration fails explicitly and never falls back to
// the debug key; debug builds never require these values.
tasks.matching { it.name.contains("Release", ignoreCase = true) }.configureEach {
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
            (keystore == null || !File(keystore).isFile)
        ) {
            missingFields.add("ARGUS_RELEASE_KEYSTORE (file not found)")
        }
        if (missingFields.isNotEmpty()) {
            throw GradleException(
                "Release signing configuration is incomplete: " +
                    missingFields.joinToString(", "),
            )
        }
    }
}
