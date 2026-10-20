allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// AGP creates a qualification variant for Flutter plugin library projects
// because the app consumes one. Those library variants must not run their own
// shrinker: their plugin entry-point classes are registered reflectively by the
// app and would be removed before the app's release-mode R8 pass can see them.
// The app's own qualification shrinker remains enabled so the packaged artifact
// keeps the distributable Release's optimization settings.
subprojects {
    if (name != "app") {
        afterEvaluate {
            val androidExtension = extensions.findByName("android")
            if (androidExtension is com.android.build.gradle.BaseExtension) {
                androidExtension.buildTypes.matching { it.name == "qualification" }.all {
                    isMinifyEnabled = false
                    isShrinkResources = false
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
