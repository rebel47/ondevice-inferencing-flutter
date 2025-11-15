# Building Android Native Libraries for llama.cpp

Since prebuilt Android binaries are not available in llama.cpp releases, you need to build them from source.

## Prerequisites

### 1. Install Required Tools

```powershell
# Check if Android SDK is installed
$env:ANDROID_HOME

# Check if Android NDK is installed
dir $env:ANDROID_HOME\ndk
```

**Required:**
- ✅ Android SDK (you already have this with Android Studio)
- ✅ Android NDK r27 or later
- ✅ CMake 3.18.1+ (included with Android Studio)
- ✅ Git for Windows

### 2. Install Android NDK

If NDK is not installed:

1. Open **Android Studio**
2. Go to: `Tools` → `SDK Manager`
3. Click `SDK Tools` tab
4. Check: ☑️ `NDK (Side by side)`
5. Check: ☑️ `CMake`
6. Click `Apply` and wait for download

## Build Instructions

### Step 1: Clone llama.cpp Repository

```powershell
# Navigate to a temporary build directory
cd F:\Startup\Temp  # or any other folder

# Clone llama.cpp
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp
```

### Step 2: Set Environment Variables

```powershell
# Set Android NDK path (adjust version number if different)
$env:ANDROID_NDK = "$env:LOCALAPPDATA\Android\Sdk\ndk\27.0.12077973"

# Verify NDK exists
Test-Path $env:ANDROID_NDK
```

### Step 3: Build for ARM64-v8a (Primary Architecture)

```powershell
# Create build directory
mkdir build-android-arm64
cd build-android-arm64

# Configure CMake for Android ARM64
cmake .. `
  -DCMAKE_TOOLCHAIN_FILE="$env:ANDROID_NDK/build/cmake/android.toolchain.cmake" `
  -DANDROID_ABI=arm64-v8a `
  -DANDROID_PLATFORM=android-24 `
  -DBUILD_SHARED_LIBS=ON `
  -DCMAKE_BUILD_TYPE=Release

# Build (this will take 5-15 minutes)
cmake --build . --config Release -j8

# Libraries will be in: build-android-arm64/src/
```

### Step 4: Build for ARMeabi-v7a (Backward Compatibility)

```powershell
# Go back to root
cd ..

# Create build directory
mkdir build-android-armv7
cd build-android-armv7

# Configure CMake for Android ARMv7
cmake .. `
  -DCMAKE_TOOLCHAIN_FILE="$env:ANDROID_NDK/build/cmake/android.toolchain.cmake" `
  -DANDROID_ABI=armeabi-v7a `
  -DANDROID_PLATFORM=android-24 `
  -DBUILD_SHARED_LIBS=ON `
  -DCMAKE_BUILD_TYPE=Release

# Build
cmake --build . --config Release -j8
```

### Step 5: Copy Libraries to Flutter Project

```powershell
# Set your project path
$PROJECT = "F:\Startup\OnDevice SLM Inferecing\ondevice_slm_app"

# Copy ARM64 libraries
Copy-Item "build-android-arm64/src/libllama.so" `
  "$PROJECT\android\app\src\main\jniLibs\arm64-v8a\"

Copy-Item "build-android-arm64/ggml/src/libggml_shared.so" `
  "$PROJECT\android\app\src\main\jniLibs\arm64-v8a\"

# Copy ARMv7 libraries
Copy-Item "build-android-armv7/src/libllama.so" `
  "$PROJECT\android\app\src\main\jniLibs\armeabi-v7a\"

Copy-Item "build-android-armv7/ggml/src/libggml_shared.so" `
  "$PROJECT\android\app\src\main\jniLibs\armeabi-v7a\"
```

### Step 6: Verify Files

```powershell
cd $PROJECT
Get-ChildItem android\app\src\main\jniLibs\*\*.so | Select-Object Name, @{Name="Size(MB)";Expression={[math]::Round($_.Length/1MB, 2)}}
```

**Expected output:**
```
Name                Length(MB)
----                ----------
libggml_shared.so   10-20 MB
libllama.so         20-60 MB
libggml_shared.so   8-18 MB
libllama.so         18-55 MB
```

### Step 7: Rebuild Flutter App

```powershell
flutter clean
flutter pub get
flutter run
```

## Troubleshooting

### CMake Not Found
```powershell
# Install via Android Studio SDK Manager
# OR download from: https://cmake.org/download/
```

### NDK Not Found
```powershell
# Verify path:
dir "$env:LOCALAPPDATA\Android\Sdk\ndk"

# If different version, update $env:ANDROID_NDK
```

### Build Errors

**Error:** `ninja: error: loading 'build.ninja'`
- **Solution:** Delete build directory and re-run cmake

**Error:** `undefined reference to 'ggml_*'`
- **Solution:** Add `-DBUILD_SHARED_LIBS=ON` to cmake command

**Error:** `Android API level too low`
- **Solution:** Use `-DANDROID_PLATFORM=android-24` (or higher)

### Libraries Too Large

If build libraries are >100 MB each:
```powershell
# Rebuild with optimizations
cmake .. -DCMAKE_BUILD_TYPE=MinSizeRel ...
```

## Alternative: Use Prebuilt from Third-Party

Some community members publish prebuilt Android binaries:

1. Check llama.cpp GitHub Issues/Discussions
2. Search for "Android prebuilt" or "Android .so"
3. **⚠️ VERIFY SOURCE** before downloading third-party binaries

## Expected Build Time

- **Clone repository:** 2-5 minutes
- **CMake configuration:** 1-2 minutes (per architecture)
- **Build compilation:** 5-15 minutes (per architecture)
- **Total time:** ~20-40 minutes

## Next Steps

After copying `.so` files to your project:

1. ✅ Verify files exist: `dir android\app\src\main\jniLibs\*\*.so`
2. ✅ Clean and rebuild: `flutter clean; flutter run`
3. ✅ Test model loading: Select your imported GGUF model
4. ✅ Expected: No more TimeoutException!

## Need Help?

- llama.cpp build docs: https://github.com/ggerganov/llama.cpp/blob/master/docs/build.md#android
- Android NDK docs: https://developer.android.com/ndk/guides
- CMake Android toolchain: https://cmake.org/cmake/help/latest/manual/cmake-toolchains.7.html#cross-compiling-for-android
