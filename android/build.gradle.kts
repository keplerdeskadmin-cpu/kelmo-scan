allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Workaround: camera_android_camerax ne concurrent-futures declare nahi kiya (Gradle 9 strict classpath)
subprojects {
    if (name == "camera_android_camerax") {
        plugins.withId("com.android.library") {
            project.dependencies.add("implementation", "androidx.concurrent:concurrent-futures:1.2.0")
        }
    }
}

// Workaround: file_picker 8.x android-34 par compile hota hai, lifecycle plugin ko 36 chahiye
subprojects {
    if (name == "file_picker") {
        val fix = Action<Project> {
            (extensions.findByName("android") as? com.android.build.gradle.BaseExtension)
                ?.compileSdkVersion(36)
        }
        if (state.executed) fix.execute(this) else afterEvaluate(fix)
    }
}
