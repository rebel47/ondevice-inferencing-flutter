# On-Device LLM Inference Setup Guide

This Flutter app uses `llama_cpp_dart` for on-device LLM inference. Follow these steps to set up the required native libraries.

## Prerequisites

- Flutter SDK (3.0.0 or later)
- Android NDK (for Android builds)
- Xcode (for iOS builds)
- Git

## Building llama.cpp Native Libraries

The `llama_cpp_dart` package requires compiled native libraries from llama.cpp. You need to build these for your target platforms.

### For Android

1. **Install Android NDK** (if not already installed):
   - Open Android Studio → SDK Manager → SDK Tools
   - Check "NDK (Side by side)" and install
   - Or download from: https://developer.android.com/ndk/downloads

2. **Clone llama.cpp**:
   ```bash
   git clone https://github.com/ggml-org/llama.cpp
   cd llama.cpp
   ```

3. **Build for Android**:
   ```bash
   # For ARM64 (most modern Android devices)
   mkdir build-android
   cd build-android
   
   cmake .. \
     -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
     -DANDROID_ABI=arm64-v8a \
     -DANDROID_PLATFORM=android-24 \
     -DCMAKE_BUILD_TYPE=Release \
     -DBUILD_SHARED_LIBS=ON
   
   cmake --build . --config Release
   ```

4. **Copy the library**:
   ```bash
   # Copy libllama.so to your Flutter project
   cp libllama.so /path/to/your/flutter_app/android/app/src/main/jniLibs/arm64-v8a/
   ```

### For iOS/macOS

1. **Clone llama.cpp** (if not done already):
   ```bash
   git clone https://github.com/ggml-org/llama.cpp
   cd llama.cpp
   ```

2. **Build for iOS**:
   ```bash
   mkdir build-ios
   cd build-ios
   
   cmake .. \
     -DCMAKE_SYSTEM_NAME=iOS \
     -DCMAKE_OSX_ARCHITECTURES=arm64 \
     -DCMAKE_BUILD_TYPE=Release \
     -DBUILD_SHARED_LIBS=ON
   
   cmake --build . --config Release
   ```

3. **For macOS**:
   ```bash
   mkdir build-macos
   cd build-macos
   
   cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON
   cmake --build . --config Release
   ```

### Alternative: Pre-built Libraries

If building from source is challenging, you can:

1. Check the [llama.cpp releases](https://github.com/ggerganov/llama.cpp/releases) for pre-built binaries
2. Use the libraries from the `llama_cpp_dart` example (if available)

## Setting Up the Library Path

In your Dart code, set the library path before using the model:

```dart
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

// For Android
Llama.libraryPath = "libllama.so";  // Automatically found in jniLibs

// For iOS/macOS
Llama.libraryPath = "/path/to/libllama.dylib";
```

## Downloading Models

1. Download GGUF format models from Hugging Face:
   - [Phi-3-Mini GGUF](https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf)
   - [Gemma GGUF](https://huggingface.co/google/gemma-2b-it-gguf)
   - [SmolLM GGUF](https://huggingface.co/HuggingFaceTB/SmolLM-135M-Instruct-GGUF)

2. Place models in `assets/models/` directory or use the app's download feature

3. Recommended quantization: Q4_K_M for balance of quality and size

## Running the App

```bash
flutter clean
flutter pub get
flutter run
```

## Troubleshooting

### "Library not found" error
- Ensure the native library is correctly placed in the appropriate directory
- Check that the library path is set correctly in your code

### Out of memory errors
- Use smaller models (e.g., SmolLM 135M)
- Use higher quantization (Q4_K_M, Q3_K_M)
- Reduce context size in model parameters

### Build errors on Android
- Ensure NDK is properly installed
- Check that CMake version is 3.19 or later
- Clean build with `flutter clean` and try again

## References

- [llama_cpp_dart documentation](https://pub.dev/packages/llama_cpp_dart)
- [llama.cpp repository](https://github.com/ggerganov/llama.cpp)
- [GGUF model format](https://github.com/ggerganov/llama.cpp/blob/master/docs/gguf.md)
