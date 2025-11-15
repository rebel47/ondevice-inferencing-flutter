# Building Native Libraries for llama_cpp_dart

## The Problem
The `llama_cpp_dart` package is just a Dart wrapper. It requires native `.so` (shared object) libraries compiled from the `llama.cpp` C++ code to actually run AI models on Android.

**Your timeout error is caused by missing native libraries** - the Dart code is waiting for a response from C++ code that doesn't exist.

## Solution: Build the Native Libraries

### Option 1: Use Prebuilt Libraries (Fastest ⚡)

Download prebuilt Android libraries from llama.cpp releases:

1. Go to: https://github.com/ggerganov/llama.cpp/releases
2. Download the latest Android release (look for `llama-*-android.zip`)
3. Extract the archive
4. Copy the `.so` files to your project:

```
llama-android.zip
├── lib/
    ├── arm64-v8a/
    │   ├── libllama.so
    │   └── libggml_shared.so
    └── armeabi-v7a/
        ├── libllama.so
        └── libggml_shared.so
```

Copy to:
```
android/app/src/main/jniLibs/
├── arm64-v8a/
│   ├── libllama.so
│   └── libggml_shared.so
└── armeabi-v7a/
    ├── libllama.so
    └── libggml_shared.so
```

### Option 2: Build from Source (Advanced)

If prebuilt libraries don't work, build them yourself:

#### Requirements:
- Android NDK r27 (already installed with Flutter)
- CMake 3.18.1+
- Git

#### Steps:

1. **Clone llama.cpp:**
```bash
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
```

2. **Build for Android arm64-v8a (modern phones):**
```bash
mkdir build-android-arm64
cd build-android-arm64

cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON

cmake --build . --config Release
```

3. **Build for Android armeabi-v7a (older phones):**
```bash
cd ..
mkdir build-android-arm32
cd build-android-arm32

cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=armeabi-v7a \
  -DANDROID_PLATFORM=android-24 \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON

cmake --build . --config Release
```

4. **Copy the built libraries:**
```bash
# From llama.cpp directory
mkdir -p ../ondevice_slm_app/android/app/src/main/jniLibs/arm64-v8a
mkdir -p ../ondevice_slm_app/android/app/src/main/jniLibs/armeabi-v7a

cp build-android-arm64/libllama.so ../ondevice_slm_app/android/app/src/main/jniLibs/arm64-v8a/
cp build-android-arm64/libggml_shared.so ../ondevice_slm_app/android/app/src/main/jniLibs/arm64-v8a/

cp build-android-arm32/libllama.so ../ondevice_slm_app/android/app/src/main/jniLibs/armeabi-v7a/
cp build-android-arm32/libggml_shared.so ../ondevice_slm_app/android/app/src/main/jniLibs/armeabi-v7a/
```

### Option 3: Quick Test with Desktop Build

For testing on desktop (not Android), you can use your computer's architecture:

**Windows:**
```powershell
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
mkdir build
cd build
cmake .. -DBUILD_SHARED_LIBS=ON
cmake --build . --config Release
```

Then set the library path in your Dart code:
```dart
Llama.libraryPath = "path/to/llama.cpp/build/bin/Release/llama.dll";
```

## Configure Android Build

After copying the `.so` files, update your `android/app/build.gradle.kts`:

```kotlin
android {
    // ... existing config ...
    
    packaging {
        jniLibs {
            // Prevent stripping debug symbols from native libraries
            keepDebugSymbols += "**/arm64-v8a/*.so"
            keepDebugSymbols += "**/armeabi-v7a/*.so"
        }
    }
}
```

## Verify Installation

1. Check the files exist:
```bash
ls -la android/app/src/main/jniLibs/arm64-v8a/
# Should show: libllama.so, libggml_shared.so
```

2. Rebuild your app:
```bash
flutter clean
flutter pub get
flutter build apk --debug
```

3. Check the APK contains the libraries:
```bash
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep "\.so"
```

You should see:
```
lib/arm64-v8a/libllama.so
lib/arm64-v8a/libggml_shared.so
lib/armeabi-v7a/libllama.so
lib/armeabi-v7a/libggml_shared.so
```

## Troubleshooting

### Model still won't load?
- Check file permissions on the `.gguf` model file
- Verify the model path is absolute: `/data/user/0/com.example.ondevice_slm_app/app_flutter/models/model.gguf`
- Try a smaller model first (< 500MB)

### Build errors?
- Ensure Android NDK is installed: `flutter doctor -v`
- Check NDK version matches requirements
- Try a clean build: `flutter clean && flutter pub get`

### Wrong architecture?
- Modern phones (2017+) use `arm64-v8a`
- Check your device: `adb shell getprop ro.product.cpu.abi`

## Next Steps

After copying the native libraries:
1. ✅ Run `flutter clean`
2. ✅ Run `flutter pub get`
3. ✅ Run `flutter run` and try importing a model again
4. ✅ Check logcat for any native library loading errors: `adb logcat | grep llama`
