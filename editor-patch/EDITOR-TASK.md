## EXACT FILES TO CREATE / MODIFY

You are patching a Flutter 3.11 app at `/home/house/projects/editor/`.
Make ONLY these changes. Do not refactor anything else.

---

### FILE 1 — CREATE: `lib/services/holmes_service.dart`

```dart
import 'dart:io';
import 'dart:typed_data' show Uint8List, ByteData, Endian;
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// binary layout of a .holmes file:
///   offset  length  field
///   0       6       magic: "HOLMES"
///   6       2       version: uint16 big-endian (= 1)
///   8       2       mime_len: uint16 big-endian = N
///   10      N       mime string (ascii)
///   10+N   8       payload_len: uint64 big-endian = M
///   10+N+8 M       payload (raw original media bytes)

class HolmesHeader {
  final int version;
  final String mimeType;
  final int payloadLength;
  final int headerSize;
  final int payloadOffset;

  HolmesHeader({
    required this.version,
    required this.mimeType,
    required this.payloadLength,
    required this.headerSize,
    required this.payloadOffset,
  });
}

class HolmesService {
  static const _magic = [72, 79, 76, 77, 69, 83]; // ASCII "HOLMES"

  /// parse a holmes header from raw bytes (no file I/O)
  HolmesHeader? parseHeader(Uint8List data) {
    if (data.length < 18) return null;
    for (var i = 0; i < 6; i++) {
      if (data[i] != _magic[i]) return null;
    }
    final version = ByteData.view(data.buffer).getUint16(6, Endian.big);
    final mimeLen = ByteData.view(data.buffer).getUint16(8, Endian.big);
    if (data.length < 10 + mimeLen + 8) return null;
    final mimeType = utf8.decode(data.sublist(10, 10 + mimeLen), allowMalformed: true);
    final payloadOffset = 10 + mimeLen + 8;
    final payloadLen = ByteData.view(data.buffer).getUint64(10 + mimeLen, Endian.big);
    return HolmesHeader(
      version: version,
      mimeType: mimeType,
      payloadLength: payloadLen,
      headerSize: payloadOffset,
      payloadOffset: payloadOffset,
    );
  }

  /// read and parse the header of a .holmes file
  Future<HolmesHeader?> readHeader(String holmesPath) async {
    try {
      final file = File(holmesPath);
      final data = await file.readAsBytes();
      return parseHeader(data);
    } catch (_) {
      return null;
    }
  }

  /// extract the payload to a temp file; returns (tempFilePath, header)
  Future<(String, HolmesHeader)> extractToTemp(String holmesPath,
      {String? suffix}) async {
    final file = File(holmesPath);
    final data = await file.readAsBytes();
    final header = parseHeader(data);
    if (header == null) {
      throw Exception('not a valid .holmes file: $holmesPath');
    }
    final payload = data.sublist(header.payloadOffset,
        header.payloadOffset + header.payloadLength);
    final cacheDir = await getTemporaryDirectory();
    final base = p.basename(p.withoutExtension(holmesPath));
    final ext = _mimeToExt(header.mimeType);
    final tempName = '${p.withoutExtension(base)}_holmes_extracted$ext${suffix ?? ""}';
    final tempPath = p.join(cacheDir.path, tempName);
    await File(tempPath).writeAsBytes(payload);
    return (tempPath, header);
  }

  /// remove a temp file created by [extractToTemp]
  Future<void> cleanupTemp(String tempPath) async {
    try {
      final f = File(tempPath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// close all temp files matching the holmes extract pattern in the temp dir
  /// call this during app shutdown or periodically to avoid disk buildup
  Future<void> cleanupAllHolmesExtracts({int olderThanHours = 24}) async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final cutoff = DateTime.now().subtract(Duration(hours: olderThanHours));
      await for (final entity in cacheDir.list()) {
        if (entity is File && entity.path.contains('_holmes_extracted')) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
  }

  /// determine FileType from a MIME type string
  static FileType mimeToFileType(String mime) {
    if (mime.startsWith('image/')) return FileType.image;
    if (mime.startsWith('video/')) return FileType.video;
    if (mime.startsWith('audio/')) return FileType.audio;
    return FileType.other;
  }

  /// guess a file extension from a MIME type
  static String _mimeToExt(String mime) {
    switch (mime) {
      case 'image/jpeg': return '.jpg';
      case 'image/png': return '.png';
      case 'image/gif': return '.gif';
      case 'image/webp': return '.webp';
      case 'image/bmp': return '.bmp';
      case 'image/svg+xml': return '.svg';
      case 'video/mp4': return '.mp4';
      case 'video/webm': return '.webm';
      case 'video/quicktime': return '.mov';
      case 'video/x-matroska': return '.mkv';
      case 'audio/mpeg': return '.mp3';
      case 'audio/wav': return '.wav';
      case 'audio/flac': return '.flac';
      case 'audio/mp4': return '.m4a';
      case 'audio/ogg': return '.ogg';
      case 'audio/aac': return '.aac';
      default: return '';
    }
  }
}

// provider
final holmesServiceProvider = Provider((ref) => HolmesService());
```

---

### FILE 2 — MODIFY: `lib/models/file_item.dart`

Add these two getters to the FileItem class (append before the `==` operator):

```dart
  /// true if this file wraps a .holmes container
  bool get isHolmes => extension == 'holmes';

  /// inner media MIME type for .holmes files (null if not a holmes file)
  /// requires holmes_service.dart to be imported at the top of the file
  String? get holmesMimeType {
    if (!isHolmes) return null;
    // synchronous lightweight approximation: look at magic bytes
    try {
      final bytes = File(path).readAsBytesSync();
      final header = HolmesService().parseHeader(bytes);
      return header?.mimeType;
    } catch (_) {
      return null;
    }
  }
```

Add this import at the top of file_item.dart:
```dart
import '../services/holmes_service.dart';
```

---

### FILE 3 — MODIFY: `lib/screens/browser_screen.dart`

**a) Update `_showContextMenu` — when a holmes file is clicked, call `_openHolmesFile`:**

Find the section inside `_showContextMenu(...).then(...)`:
```
      } else if (value == 'open' && file != null) {
        ref.openEditor(file);
      }
```
replace with:
```
      } else if (value == 'open' && file != null && file.isHolmes) {
        _openHolmesFile(context, ref, file);
      } else if (value == 'open' && file != null) {
        ref.openEditor(file);
      }
```

**b) Add `_openHolmesFile` method** — insert after `_deleteFile` method:

```dart
  Future<void> _openHolmesFile(
      BuildContext context, WidgetRef ref, FileItem file) async {
    try {
      final holmesService = ref.read(holmesServiceProvider);
      final (tempPath, header) = await holmesService.extractToTemp(file.path);

      if (!mounted) return;

      final innerType = HolmesService.mimeToFileType(header.mimeType);
      final guessedExt = HolmesService._mimeToExt(header.mimeType);
      final innerName = p.basenameWithoutExtension(file.name) + guessedExt;

      final innerFile = FileItem(
        name: innerName.isNotEmpty ? innerName : file.name,
        path: tempPath,
        size: header.payloadLength,
        lastModified: file.lastModified,
        isDirectory: false,
        isRemote: false,
        type: innerType,
      );

      ref.read(selectedFileInBrowserProvider.notifier).state = innerFile;
      ref.openEditor(innerFile);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('failed to open .holmes: $e')),
      );
    }
  }
```

**c) Add `_mimeToFileType` static helper in the `FileDetailsPanel` section:**

After `IconData _getIcon(FileType type)` method, add:
```dart
  static FileType _mimeToFileType(String mime) {
    if (mime.startsWith('image/')) return FileType.image;
    if (mime.startsWith('video/')) return FileType.video;
    if (mime.startsWith('audio/')) return FileType.audio;
    return FileType.other;
  }
```

**d) In `FileDetailsPanel`, show inner MIME for holmes files:**

Find the line `_DetailRow(label: 'type', value: file.type.name.toLowerCase()),`
and replace with:
```dart
          _DetailRow(
            label: 'type',
            value: file.isHolmes
                ? (file.holmesMimeType ?? 'holmes container')
                : file.type.name.toLowerCase(),
          ),
```

**e) In `FileGridItem._buildIcon`**, add a holmes icon before the `default` case:

In the switch block, add after `case FileType.archive:`:
```dart
      case FileType.holmes:
        icon = Icons.inbox;
        iconColor = AppTheme.primaryColor;
        break;
```

Wait — FileType does NOT have a holmes value. Instead, use the existing `FileType.other` branch,
and override it conditionally in the buildIcon:

Actually, simplest approach: in the `switch(file.type)` block in `_buildIcon`,
add a `case FileType.other:` replacement:

```dart
      case FileType.other:
        if (file.isHolmes) {
          return Icon(Icons.inbox, size: 24, color: AppTheme.primaryColor);
        }
        return Image.asset(
          'assets/file.png',
          color: theme.colorScheme.primary,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.insert_drive_file,
            size: 24,
            color: theme.colorScheme.primary,
          ),
        );
```

**f) Add required import at top of browser_screen.dart** (for `file` access in `_buildIcon`):
`import 'dart:io';`
(the file already has `import 'dart:io';` — confirm it's there)

---

### VERIFICATION

After changes:
```
cd /home/house/projects/editor && flutter pub get && flutter analyze
```

If flutter analyze shows any issues with holmes_service.dart, fix them.
Then commit ALL changes with message: "feat: add .holmes container format support"
