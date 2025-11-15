plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.ondevice_slm_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.ondevice_slm_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26  // Required by llama_flutter_android (Android 8.0+)
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
    externalNativeBuild {
        cmake {
            version = "3.22.1"
        }
    }
    
    // CRITICAL: Prevent Android from stripping the llama.cpp native libraries
    // Without this, the .so files will be removed during build
    packaging {
        jniLibs {
            // Keep all .so files in these directories
            keepDebugSymbols.add("**/arm64-v8a/*.so")
            keepDebugSymbols.add("**/armeabi-v7a/*.so")
        }
        // Also prevent any compression or removal
        resources {
            pickFirsts.add("lib/arm64-v8a/libllama.so")
            pickFirsts.add("lib/arm64-v8a/libggml_shared.so")
            pickFirsts.add("lib/armeabi-v7a/libllama.so")
            pickFirsts.add("lib/armeabi-v7a/libggml_shared.so")
        }
    }
}

flutter {
    source = "../.."
}
