plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.argusromtoolkit.argus"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.argusromtoolkit.argus"
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
