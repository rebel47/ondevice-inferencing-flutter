# Native Library Installation Checklist

## ✅ Status Check

### Step 1: Directory Structure ✅ DONE
```
android/app/src/main/jniLibs/
├── arm64-v8a/        ✅ Created
├── armeabi-v7a/      ✅ Created
└── README.md         ✅ Created
```

### Step 2: build.gradle.kts Configuration ✅ DONE
File: `android/app/build.gradle.kts`

Added packaging configuration to prevent stripping:
```kotlin
packaging {
    jniLibs {
        keepDebugSymbols.add("**/arm64-v8a/*.so")
        keepDebugSymbols.add("**/armeabi-v7a/*.so")
    }
    resources {
        pickFirsts.add("lib/arm64-v8a/libllama.so")
        pickFirsts.add("lib/arm64-v8a/libggml_shared.so")
        pickFirsts.add("lib/armeabi-v7a/libllama.so")
        pickFirsts.add("lib/armeabi-v7a/libggml_shared.so")
    }
}
```

### Step 3: Download Native Libraries ⚠️ TODO

You need to manually download and place these files:

#### Required Files:
- `android/app/src/main/jniLibs/arm64-v8a/libllama.so`
- `android/app/src/main/jniLibs/arm64-v8a/libggml_shared.so`
- `android/app/src/main/jniLibs/armeabi-v7a/libllama.so`
- `android/app/src/main/jniLibs/armeabi-v7a/libggml_shared.so`

## 📥 How to Download

### Option 1: From GitHub Releases (Recommended)

1. **Open**: https://github.com/ggerganov/llama.cpp/releases

2. **Find the latest release** (look for recent releases like `b4600`, `b4700`, etc.)

3. **Download Android binaries**:
   - Look for files named:
     - `llama-*-android-arm64-v8a.zip`
     - `llama-*-android-armeabi-v7a.zip`
   - OR a combined: `llama-*-android.zip`

4. **Extract the ZIP files**

5. **Find the .so files**:
   ```
   Inside the ZIP:
   ├── libllama.so
   └── libggml_shared.so  (or similar names)
   ```

6. **Copy to your project**:
   - Copy ARM64 version to: `android/app/src/main/jniLibs/arm64-v8a/`
   - Copy ARMv7 version to: `android/app/src/main/jniLibs/armeabi-v7a/`

### Option 2: Build from Source (Advanced)

If prebuilt binaries aren't available, see `BUILD_NATIVE_LIBS.md` for compilation instructions.

## 🔍 Verification

### Check 1: Files Exist
```powershell
dir android\app\src\main\jniLibs\*\*.so
```

**Expected output:**
```
android\app\src\main\jniLibs\arm64-v8a\libllama.so
android\app\src\main\jniLibs\arm64-v8a\libggml_shared.so
android\app\src\main\jniLibs\armeabi-v7a\libllama.so
android\app\src\main\jniLibs\armeabi-v7a\libggml_shared.so
```

### Check 2: File Sizes
```powershell
Get-ChildItem -Path android\app\src\main\jniLibs -Recurse -Filter *.so | Select-Object Name, @{Name="Size(MB)";Expression={[math]::Round($_.Length/1MB, 2)}}
```

**Expected:**
- `libllama.so` should be 20-60 MB
- `libggml_shared.so` should be 5-20 MB

### Check 3: Build and Verify APK
```bash
flutter clean
flutter pub get
flutter build apk --debug
```

Then check APK contents:
```powershell
Expand-Archive -Path build\app\outputs\flutter-apk\app-debug.apk -DestinationPath temp_apk -Force
dir temp_apk\lib\arm64-v8a\*.so
Remove-Item -Path temp_apk -Recurse -Force
```

**Expected:** You should see `libllama.so` and `libggml_shared.so` in the APK

## 🚀 After Installing Libraries

Once you've placed the `.so` files, run:

```bash
# 1. Clean the project
flutter clean

# 2. Get dependencies
flutter pub get

# 3. Run on device
flutter run
```

## 🎯 Expected Result

After installing native libraries:

✅ No more TimeoutException
✅ Models load successfully
✅ GGUF models work properly
✅ AI inference functions

## 📝 Quick Links

- llama.cpp Releases: https://github.com/ggerganov/llama.cpp/releases
- llama.cpp Android Build Guide: https://github.com/ggerganov/llama.cpp/blob/master/docs/build.md#android

## 🆘 Troubleshooting

**Still getting TimeoutException?**
1. Verify files exist with correct names
2. Check file permissions (should be readable)
3. Try `flutter clean && flutter pub get`
4. Check logcat: `adb logcat | findstr llama`

**Build errors?**
1. Ensure `build.gradle.kts` has the packaging configuration
2. Try invalidating caches: Delete `android/.gradle` folder
3. Rebuild: `flutter clean && flutter build apk`

**Wrong architecture?**
- Your Galaxy S24 Ultra uses `arm64-v8a`
- Most modern phones (2017+) use `arm64-v8a`
- Check with: `adb shell getprop ro.product.cpu.abi`
