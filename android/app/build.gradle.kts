plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.kelmo.scan"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.kelmo.scan"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Fixed release key (from GitHub secrets in CI) so every new APK installs as an UPDATE.
    val ks = System.getenv("KELMO_KEYSTORE")
    signingConfigs {
        if (ks != null && file(ks).exists()) {
            create("kelmo") {
                storeFile = file(ks)
                storePassword = System.getenv("KELMO_KEYSTORE_PASS")
                keyAlias = "kelmo"
                keyPassword = System.getenv("KELMO_KEYSTORE_PASS")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("kelmo") ?: signingConfigs.getByName("debug")
            // OpenCV + tesseract4android use JNI; keep all classes/names intact.
            isMinifyEnabled = false
            isShrinkResources = false
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

dependencies {
    implementation("org.opencv:opencv:4.9.0")
    implementation("androidx.exifinterface:exifinterface:1.3.7")
implementation("androidx.appcompat:appcompat:1.6.1")
implementation("androidx.biometric:biometric:1.1.0")
implementation("cz.adaptech.tesseract4android:tesseract4android:4.9.0")
}
