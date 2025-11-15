# OnDevice SLM App

A Flutter application for running large language models (LLMs) entirely on-device with a modern, privacy-focused interface.

## Features

- 🔒 **Fully Offline** - No internet required, all processing happens on your device
- 🛡️ **Private & Secure** - Your data never leaves your device
- ⚡ **Fast Inference** - Optimized for mobile with GGUF quantized models
- 🎨 **Modern UI** - Clean Material Design 3 interface with gradient backgrounds
- 📱 **Easy Model Management** - Import GGUF models directly from your device
- 💬 **Real-time Chat** - Streaming token generation with modern chat bubbles

## Getting Started

### Prerequisites
- Flutter SDK (stable channel) - [Installation Guide](https://flutter.dev/docs/get-started/install)
- Android NDK 27.0.12077973 (for building native libraries)
- CMake 3.18.1 or higher

### Installation

1. Clone the repository:
```powershell
git clone https://github.com/rebel47/ondevice-inferencing-flutter.git
cd ondevice_slm_app
```

2. Install dependencies:
```powershell
flutter pub get
```

3. Run the app:
```powershell
flutter run -d <device-id>   # or 'flutter run' to choose a device
```

### Development Commands

Run tests:
```powershell
flutter test
```

Format code:
```powershell
flutter format .
```

Analyze code:
```powershell
flutter analyze
```

## On-Device LLM Inference

This app uses `llama_cpp_dart` (v0.1.2+1) to run GGUF quantized models directly on your device.

### Supported Models
- Any GGUF format model (Llama, Phi, Gemma, etc.)
- Recommended: 4-bit quantized models for optimal performance
- Examples: `phi-3-mini-q4.gguf`, `gemma-2b-q4.gguf`, `llama-3.2-1b-q4.gguf`

### How to Add Models

**Option 1: Direct File Placement (Recommended for Large Models)**

For models larger than 1GB, place them directly in the app's external storage directory to avoid memory issues:

1. Connect your Android device to your computer
2. Navigate to: `Android/data/com.example.ondevice_slm_app/files/models/`
3. Copy your GGUF model files to this directory
4. Restart the app - models will be automatically detected

**Option 2: Import from Device (Best for Small Models < 1GB)**

1. Launch the app and navigate to the Chat screen
2. Tap the model selector icon in the app bar
3. Select "Import from device"
4. Read the warning about file size limitations
5. Choose your GGUF model file from the file picker
6. The app will copy it to app storage for future use

> ⚠️ **Note**: The Android file picker may crash with very large files (>1GB) due to memory limitations. Use Option 1 for large models.

**Option 3: Pre-bundle Models**
1. Place GGUF files in `assets/models/` directory
2. Add them to `pubspec.yaml` under assets
3. Run `flutter pub get`
4. The app will detect and list them automatically

**Option 3: Download from URL**
- Update `ChatScreen._pickModelFromDevice()` to support HTTP downloads
- Implement progress tracking for large file downloads

### Performance Notes

- **Quantization**: 4-bit (Q4) models offer the best balance of speed and quality
- **Model Size**: Smaller models (1B-3B parameters) run faster on mobile devices
- **Memory**: Ensure device has sufficient RAM (4GB+ recommended for 3B models)
- **Storage**: Models can be 500MB-2GB+ depending on size and quantization

### File Picker & Permissions

**File Size Limitations:**
- The Android file picker has memory constraints and may crash with files >1GB
- This is a limitation of the Android system, not the app
- **Workaround**: Place large model files directly in `Android/data/com.example.ondevice_slm_app/files/models/`

**Storage Access:**
- The app uses Android's Storage Access Framework (SAF)
- No runtime permissions needed for the file picker
- Large file warnings alert when selecting files > 500MB
- File validation checks that selected files exist and are readable
- Persistent access - Models are copied to app storage for future use

## Architecture

```
lib/
├── main.dart                 # App entry point
├── models/
│   └── chat_message.dart    # Message data model
├── screens/
│   ├── home_screen.dart     # Landing page with app features
│   └── chat_screen.dart     # Chat interface with model management
├── services/
│   ├── inference_service.dart  # Abstract inference interface
│   └── llama_service.dart      # llama_cpp_dart implementation
└── widgets/
    └── chat_bubble.dart     # Chat message bubble component
```

## Documentation

- [Setup Guide](SETUP.md) - Native library setup and build instructions
- [UI Improvements](UI_IMPROVEMENTS.md) - Complete UI redesign documentation
- [Permission Flow](PERMISSION_FLOW.md) - File access and permission handling

## Troubleshooting

### Build Issues
- Ensure Android NDK 27 is installed
- Check CMake version (3.18.1+)
- Run `flutter clean` and rebuild

### Model Loading Fails
- Verify GGUF file is not corrupted
- Check available device memory
- Try a smaller quantized model

### File Picker Not Working
- For files >1GB, use direct file placement (see "How to Add Models")
- The app uses SAF - no permissions should be needed for smaller files
- Try restarting the app
- Check device storage is not full

## Technology Stack

- **Framework**: Flutter 3.x
- **Language**: Dart
- **LLM Runtime**: llama_cpp_dart ^0.1.2+1
- **File Picker**: file_selector ^1.0.4
- **Storage**: path_provider, shared_preferences
- **UI**: Material Design 3

## Contributing

Contributions are welcome! Please read the contribution guidelines before submitting PRs.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Built with [llama_cpp_dart](https://pub.dev/packages/llama_cpp_dart)
- Powered by [llama.cpp](https://github.com/ggerganov/llama.cpp)
- UI inspired by modern Material Design principles
