# OnDevice SLM Starter App

This is a minimal Flutter starter application scaffolded for the OnDevice SLM inference workspace.

## Getting started

Prerequisites:
- Flutter SDK installed (stable channel). Follow https://flutter.dev/docs/get-started/install

Start the app (PowerShell):

```powershell
cd "f:\Startup\OnDevice SLM Inferecing\ondevice_slm_app"
flutter pub get
flutter run -d <device-id>   # or 'flutter run' to choose a device
```

Run tests:

```powershell
flutter test
```

Formatting and analyze:

```powershell
flutter format .
flutter analyze
```

This scaffold contains a simple counter and a starting Home screen. Add features as needed.

## On-device LLM (Phi-3 Mini via flutter_llama)

This project includes a `Chat` screen that uses `flutter_llama` to run a GGUF model on device. It expects a GGUF file, for example `phi-3-mini-q4.gguf`.

How to provide a model:
1. Copy a GGUF model to the `assets/models/` directory with file name `phi-3-mini.gguf` and run `flutter pub get`. The example code will copy it to the app's documents dir on launch.
2. Or host the model on HTTP and update `ChatScreen` to pass a download URL to `prepareModel`.

Notes:
- Phi-3 Mini Q4 is fast on mobile with quantization; performance depends on device.
- The `flutter_llama` plugin streams tokens during generation; chat UI appends tokens as they arrive.
- Example uses `LlamaService` in `lib/services` for model handling and token streaming.

Permissions and file picker notes
- If you choose a model from the device using the app's file picker, the app may request storage permissions on Android (pre-Android 13). If the permission is denied, the file picker won't work — grant it through the system settings and try again.
- Model files can be large (100s of MB). When picking from the device the app will warn if a model is bigger than 500MB and you can cancel or continue. Copying a model to app storage will make it available for future use.
