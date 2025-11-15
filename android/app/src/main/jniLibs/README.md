# Native Libraries Directory

## Required Files

Place the compiled llama.cpp shared libraries here:

### For 64-bit ARM devices (modern phones - 2017+):
```
arm64-v8a/
├── libllama.so
└── libggml_shared.so
```

### For 32-bit ARM devices (older phones):
```
armeabi-v7a/
├── libllama.so
└── libggml_shared.so
```

## Where to Get These Files

**Option 1: Download prebuilt (recommended)**
1. Go to https://github.com/ggerganov/llama.cpp/releases
2. Download the Android release (e.g., `llama-b4355-bin-android.zip`)
3. Extract and copy the `.so` files to the appropriate directories above

**Option 2: Build from source**
See `BUILD_NATIVE_LIBS.md` in the project root for detailed instructions.

## Verification

After adding the files, verify they're included in the APK:

```bash
flutter build apk --debug
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep "\.so"
```

You should see the libraries listed in the APK.

## Current Status

⚠️ **MISSING** - The TimeoutException when loading models is because these libraries are not present.

Add the libraries here, then run:
```bash
flutter clean
flutter pub get
flutter run
```
