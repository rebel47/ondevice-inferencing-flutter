# Download and Extract llama.cpp Native Libraries for Android
# This script downloads prebuilt llama.cpp libraries and places them in the correct location

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "llama.cpp Native Library Installer" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

$LLAMA_VERSION = "b4355"  # Update this to the latest version from GitHub releases
$DOWNLOAD_URL = "https://github.com/ggerganov/llama.cpp/releases/download/b4355/llama-b4355-bin-android.zip"
$TEMP_DIR = Join-Path $env:TEMP "llama_android_libs"
$ZIP_FILE = Join-Path $TEMP_DIR "llama-android.zip"
$EXTRACT_DIR = Join-Path $TEMP_DIR "extracted"

$PROJECT_ROOT = $PSScriptRoot
$JNILIBS_DIR = Join-Path $PROJECT_ROOT "android\app\src\main\jniLibs"

Write-Host "[CHECK] Looking for existing libraries..." -ForegroundColor Yellow

$arm64Dir = Join-Path $JNILIBS_DIR "arm64-v8a"
$arm32Dir = Join-Path $JNILIBS_DIR "armeabi-v7a"

if ((Test-Path (Join-Path $arm64Dir "libllama.so")) -and (Test-Path (Join-Path $arm32Dir "libllama.so"))) {
    Write-Host "[OK] Native libraries already exist!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Files found:" -ForegroundColor Green
    Get-ChildItem -Path $arm64Dir, $arm32Dir -Filter "*.so" -Recurse | ForEach-Object {
        $size = [math]::Round($_.Length / 1MB, 2)
        $relPath = $_.FullName.Replace($PROJECT_ROOT, '.')
        Write-Host "  * $relPath ($size MB)" -ForegroundColor Gray
    }
    Write-Host ""
    $overwrite = Read-Host "Do you want to download and overwrite them? (y/N)"
    if ($overwrite -ne "y" -and $overwrite -ne "Y") {
        Write-Host "Keeping existing libraries. Run 'flutter clean && flutter pub get' to use them." -ForegroundColor Cyan
        exit 0
    }
}

Write-Host ""
Write-Host "[DOWNLOAD] Fetching llama.cpp Android libraries..." -ForegroundColor Yellow
Write-Host "   Version: $LLAMA_VERSION" -ForegroundColor Gray
Write-Host "   URL: $DOWNLOAD_URL" -ForegroundColor Gray
Write-Host ""

# Create temp directory
New-Item -ItemType Directory -Force -Path $TEMP_DIR | Out-Null
New-Item -ItemType Directory -Force -Path $EXTRACT_DIR | Out-Null

try {
    # Download with progress
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile $ZIP_FILE -ErrorAction Stop
    $ProgressPreference = 'Continue'
    
    $downloadSize = [math]::Round((Get-Item $ZIP_FILE).Length / 1MB, 2)
    Write-Host "[OK] Downloaded successfully (${downloadSize}MB)" -ForegroundColor Green
    Write-Host ""
    
    # Extract
    Write-Host "[EXTRACT] Unpacking archive..." -ForegroundColor Yellow
    Expand-Archive -Path $ZIP_FILE -DestinationPath $EXTRACT_DIR -Force
    Write-Host "[OK] Extracted" -ForegroundColor Green
    Write-Host ""
    
    # Find and copy .so files
    Write-Host "[COPY] Installing native libraries..." -ForegroundColor Yellow
    
    # Create jniLibs directories if they don't exist
    New-Item -ItemType Directory -Force -Path $arm64Dir | Out-Null
    New-Item -ItemType Directory -Force -Path $arm32Dir | Out-Null
    
    $copiedCount = 0
    
    # Search for .so files in extracted directory
    $soFiles = Get-ChildItem -Path $EXTRACT_DIR -Recurse -Filter "*.so"
    
    foreach ($file in $soFiles) {
        if ($file.DirectoryName -match "arm64-v8a") {
            $dest = Join-Path $arm64Dir $file.Name
            Copy-Item -Path $file.FullName -Destination $dest -Force
            $size = [math]::Round($file.Length / 1MB, 2)
            Write-Host "  * arm64-v8a/$($file.Name) (${size}MB)" -ForegroundColor Gray
            $copiedCount++
        }
        elseif ($file.DirectoryName -match "armeabi-v7a") {
            $dest = Join-Path $arm32Dir $file.Name
            Copy-Item -Path $file.FullName -Destination $dest -Force
            $size = [math]::Round($file.Length / 1MB, 2)
            Write-Host "  * armeabi-v7a/$($file.Name) (${size}MB)" -ForegroundColor Gray
            $copiedCount++
        }
    }
    
    if ($copiedCount -eq 0) {
        Write-Host ""
        Write-Host "[ERROR] No .so files found in the expected structure!" -ForegroundColor Red
        Write-Host "   The download format may have changed." -ForegroundColor Red
        Write-Host "   Please manually download from:" -ForegroundColor Yellow
        Write-Host "   https://github.com/ggerganov/llama.cpp/releases" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "   Extract and copy .so files to:" -ForegroundColor Yellow
        Write-Host "   - android/app/src/main/jniLibs/arm64-v8a/" -ForegroundColor Gray
        Write-Host "   - android/app/src/main/jniLibs/armeabi-v7a/" -ForegroundColor Gray
        exit 1
    }
    
    Write-Host ""
    Write-Host "[SUCCESS] Installed $copiedCount native libraries!" -ForegroundColor Green
    Write-Host ""
    Write-Host "[INFO] Libraries installed in:" -ForegroundColor Cyan
    Write-Host "   $JNILIBS_DIR" -ForegroundColor Gray
    Write-Host ""
    Write-Host "[NEXT STEPS]" -ForegroundColor Cyan
    Write-Host "   1. Run: flutter clean" -ForegroundColor White
    Write-Host "   2. Run: flutter pub get" -ForegroundColor White
    Write-Host "   3. Run: flutter run" -ForegroundColor White
    Write-Host ""
    Write-Host "   Your app should now be able to load GGUF models!" -ForegroundColor Green
    
} catch {
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Manual installation instructions:" -ForegroundColor Yellow
    Write-Host "1. Download from: https://github.com/ggerganov/llama.cpp/releases" -ForegroundColor Gray
    Write-Host "2. Look for 'llama-*-bin-android.zip'" -ForegroundColor Gray
    Write-Host "3. Extract and copy .so files to:" -ForegroundColor Gray
    Write-Host "   - android/app/src/main/jniLibs/arm64-v8a/" -ForegroundColor Gray
    Write-Host "   - android/app/src/main/jniLibs/armeabi-v7a/" -ForegroundColor Gray
    exit 1
} finally {
    # Cleanup
    if (Test-Path $TEMP_DIR) {
        Remove-Item -Path $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue
    }
}
