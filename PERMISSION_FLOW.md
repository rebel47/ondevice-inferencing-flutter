# Permission Flow Guide

## Storage Permission Request Flow

### 1. User Action
User clicks "Import from device" in the model selector menu.

### 2. Permission Check
```dart
Future<bool> _requestStoragePermission()
```
The app checks the current permission status:

#### Case A: Already Granted ✅
- Permission status: `isGranted`
- Action: Proceed directly to file picker
- User Experience: Seamless, no dialogs

#### Case B: Permanently Denied 🚫
- Permission status: `isPermanentlyDenied`
- Action: Show dialog explaining the situation
- Dialog Content:
  - Icon: ⚠️ Warning icon (orange)
  - Title: "Storage Permission Required"
  - Message: Explains permanent denial and suggests opening settings
  - Buttons:
    - "Cancel": Dismisses dialog, returns to app
    - "Open Settings": Opens app settings page
- If user clicks "Open Settings":
  - `openAppSettings()` is called
  - User is taken to system settings
  - Must manually enable permission
  - Returns to app (permission still needs recheck)

#### Case C: First Time / Previously Denied ❓
- Permission status: `isDenied`
- Action: Show explanation dialog first
- Dialog Content:
  - Icon: 📁 Folder icon (blue)
  - Title: "Storage Access Needed"
  - Message: 
    - Why permission is needed
    - Privacy assurance
  - Buttons:
    - "Cancel": User declines, returns to app
    - "Grant Permission": Proceeds to system permission dialog
- If user clicks "Grant Permission":
  - System permission dialog appears
  - User can "Allow" or "Deny"
  - Result is returned

### 3. File Selection
If permission is granted:
```dart
final XFile? xfile = await openFile(
  acceptedTypeGroups: <XTypeGroup>[ggufGroup],
);
```
- System file picker opens
- Shows only .gguf files (filtered)
- User can browse and select a model file
- Returns selected file path or null if cancelled

### 4. File Validation
```dart
// Check if file exists and is readable
if (!await selectedFile.exists()) {
  _showErrorDialog('File not found', '...');
  return;
}
```
- Verifies file existence
- Shows error if file is inaccessible

### 5. Size Check
```dart
final size = await selectedFile.length();
const warnSize = 500 * 1024 * 1024; // 500MB

if (size >= warnSize) {
  final confirmed = await _showLargeFileDialog(size);
  if (!confirmed) return;
}
```
- Checks file size
- If > 500MB:
  - Shows warning dialog
  - Displays size in MB
  - Warns about memory usage
  - User can cancel or continue

### 6. File Copying
```dart
// Show loading dialog
showDialog(
  context: context,
  barrierDismissible: false,
  builder: (_) => LoadingDialog(),
);

// Copy to app directory
await selectedFile.copy(dest.path);
```
- Shows non-dismissible loading dialog
- Copies file to app's documents directory
- Updates UI when complete

### 7. Success/Error Feedback
Success:
```dart
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Row([
      Icon(Icons.check_circle, color: Colors.white),
      Text('Model "..." loaded successfully'),
    ]),
    backgroundColor: Colors.green,
  ),
);
```

Error:
```dart
_showErrorDialog('Copy failed', 'Failed to copy model file: $e');
```

## Permission Scenarios

### Scenario 1: First-Time User (Happy Path)
1. User clicks "Import from device"
2. Explanation dialog appears → User clicks "Grant Permission"
3. System dialog appears → User clicks "Allow"
4. File picker opens → User selects model.gguf
5. Loading dialog shows → File copies
6. Success SnackBar appears → Model is ready

**Duration**: ~15-30 seconds (depends on file size)

### Scenario 2: Permission Denied Once
1. User clicks "Import from device"
2. Explanation dialog appears → User clicks "Grant Permission"
3. System dialog appears → User clicks "Deny"
4. Returns to chat screen → No file selected

**Next Attempt**:
- Same flow repeats
- User can grant permission on second try

### Scenario 3: Permission Permanently Denied
1. User clicks "Import from device"
2. Warning dialog appears (no system dialog)
3. User clicks "Open Settings"
4. System settings open
5. User enables permission manually
6. Returns to app → Must retry "Import from device"

**User Action Required**: Must return to app and try again

### Scenario 4: Android 13+ (No Permission Needed)
1. User clicks "Import from device"
2. File picker opens immediately (no permission dialogs)
3. User selects file → Process continues normally

**Why**: Android 13+ uses scoped storage, file picker has built-in access

### Scenario 5: Large File Selected
1. User selects 2GB model file
2. Large file warning dialog appears
3. User can:
   - Cancel: Returns to chat
   - Continue: Shows loading dialog, begins copy
4. Copy takes 30-60 seconds
5. Success notification appears

### Scenario 6: File Access Error
Possible causes:
- File deleted after selection
- File on removable storage that was unmounted
- Insufficient app storage space
- File format corruption

Error dialog appears with specific message.

## Testing Checklist

### Permission Testing
- [ ] First request → Grant → Works
- [ ] First request → Deny → Can retry
- [ ] Permanently denied → Settings link works
- [ ] Android 13+ → No permission needed

### File Selection Testing
- [ ] Can select .gguf files
- [ ] Other file types filtered out
- [ ] Cancel selection works
- [ ] Large files show warning
- [ ] Small files skip warning

### UI Feedback Testing
- [ ] Loading dialog shows during copy
- [ ] Success SnackBar appears
- [ ] Error dialogs show on failure
- [ ] Model appears in selector after import

### Edge Cases
- [ ] No external storage available
- [ ] Insufficient space for copy
- [ ] File already exists (skip copy)
- [ ] App killed during copy (partial file)
- [ ] Rotation during dialogs

## User Messages Reference

### Permission Explanation
> "To select GGUF model files from your device, this app needs permission to access your storage.
> 
> Your privacy is protected - we only read the specific model files you choose."

### Permanent Denial
> "This app needs storage permission to access model files from your device. The permission has been permanently denied. Please enable it in app settings."

### Large File Warning
> "The selected model is XXX.X MB.
> 
> This may take time to copy and can use significant memory. Continue?"

### Success
> "Model 'filename.gguf' loaded successfully"

### Errors
- **File not found**: "The selected file could not be accessed."
- **Copy failed**: "Failed to copy model file: [error details]"
- **Selection error**: "Failed to select file: [error details]"
