## Task: Add .holmes container format support to the edit Flutter app

You are working on a Flutter 3.x media editor app at `/home/house/projects/editor/`.
The repo is already cloned. Make all code changes there.

---

### What is .holmes?

A binary container that wraps one media file without re-encoding.

Layout (see `/home/house/projects/holmes/core/bin/holmes.py` for reference):
  [ magic: "HOLMES" (6 bytes) ]
  [ version: uint16_be = 1 (2 bytes) ]
  [ mime_len: uint16_be = N (2 bytes) ]
  [ mime: N bytes ascii ]          ← original MIME type, e.g. "image/jpeg"
  [ payload_len: uint64_be = M (8 bytes) ]
  [ payload: M bytes ]             ← raw original media, untouched

The Python tools (holmes, holmes-extract, holmes-verify, holmes-info) already
exist at `/home/house/projects/holmes/core/bin/`. Use holmes.py as the format
reference; it exports struct-based `make_header`, `parse_header`, and
`detect_mime` functions that you can port to Dart.

---

### Goal

When a user browses their files in the editor and taps/open a `.holmes` file:
1. Parse the holmes header to discover the inner MIME type and payload size.
2. Extract the payload to a temp file (using path_provider's temp directory).
3. Route to the correct editor tab (image, video, or audio) with the extracted
   temp file — exactly as if the user had opened the original media file.
4. Clean up temp files when they are no longer needed.

When browsing: .holmes files should show a distinct icon (package icon or
a custom icon indicating "container / archive") and show the inner MIME type in
the details panel.

---

### Files to change

**1. `lib/models/file_item.dart`**
- Add two new **extension getters** (not enum values!) — keep the existing
  `FileType` enum untouched:

```dart
  /// true if this file is a .holmes container
  bool get isHolmes => extension == 'holmes';

  /// inner media MIME type for .holmes files (null if not a holmes file)
  String? get holmesMimeType => isHolmes ? _cachedHolmesMimeType : null;
```

- The _cachedHolmesMimeType should be computed lazily using `parseHolmesHeader()`
  from the new HolmesService. Do NOT make this synchronous on the constructor
  (it needs async file I/O). Instead, expose it via an `async` method or cache
  it when the file is first opened.

**2. NEW file: `lib/services/holmes_service.dart`**

Write a standalone `HolmesService` class that can parse .holmes headers using
pure Dart (no native deps needed — just `dart:io`, `dart:typed_data`).

```dart
class HolmesHeader {
  final int version;
  final String mimeType;
  final int payloadLength;
  final int headerSize;      // total bytes of header (18 + mimeLen)
  final int payloadOffset;   // == headerSize

  // convenience
  FileType get innerFileType => _mimeToFileType(mimeType);
}

class HolmesService {
  /// parse header from bytes — does NOT read file
  HolmesHeader? parseHeader(List<int> bytes);

  /// read file and parse header (convenience)
  Future<HolmesHeader?> readHeader(String holmesPath);

  /// read + parse + write payload to a temp file; returns (tempPath, header)
  Future<(String, HolmesHeader)> extractToTemp(String holmesPath);

  /// clean up a previously-extracted temp file
  Future<void> cleanupTemp(String tempPath);
}
```

Binary format notes for Dart:
- Read first 6 bytes → compare to [72,79,76,77,69,83] (ASCII "HOLMES")
- Bytes 6-7: `ByteData.getUint16(6, Endian.big)` → version
- Bytes 8-9: mime string length N
- Bytes 10..10+N-1: mime as utf8
- Bytes 10+N..10+N+7: raw payload length (uint64 big)
- Payload starts at offset 10+N+8

Do NOT use any external package for this — pure Dart `dart:io` + `dart:typed_data`.

**3. `lib/services/file_service.dart`**
- No changes needed to file_service for basic holmes support.
  The holmes extraction is handled by `HolmesService`.

**4. `lib/screens/browser_screen.dart`**

This is the key integration point.

In the `_showContextMenu` method, already handle .holmes files:
- `open` → call `_openHolmesFile(context, ref, file)` instead of `ref.openEditor(file)`

Add a new method `_openHolmesFile`:

```dart
Future<void> _openHolmesFile(BuildContext context, WidgetRef ref, FileItem file) async {
  final holmesService = ref.read(holmesServiceProvider);
  try {
    final (tempPath, header) = await holmesService.extractToTemp(file.path);

    // determine inner FileType from the header's mime type
    final innerType = _mimeToFileType(header.mimeType);

    // build a NEW FileItem pointing at the extracted temp file
    final innerFile = FileItem(
      name: file.name.replaceAll('.holmes', '') + _innerExt(header.mimeType),
      path: tempPath,
      size: header.payloadLength,
      lastModified: file.lastModified,
      isDirectory: false,
      isRemote: false,
      type: innerType,
    );

    // select it and open editor — this will route to the right tab
    if (!mounted) return;
    ref.read(selectedFileInBrowserProvider.notifier).state = innerFile;
    ref.openEditor(innerFile);
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('failed to open .holmes: $e')),
    );
  }
}
```

Also add `_mimeToFileType` helper to `browser_screen.dart`:

```dart
FileType _mimeToFileType(String mime) {
  if (mime.startsWith('image/')) return FileType.image;
  if (mime.startsWith('video/')) return FileType.video;
  if (mime.startsWith('audio/')) return FileType.audio;
  return FileType.other;
}
```

Optional: improve `_buildIcon` in `FileGridItem` to render a small "box/inbox"
icon for holmes files. Use `Icons.inbox` or any suitable Material icon.

In the `FileDetailsPanel` widget (same file), when `file.isHolmes`, show
an extra row: "inner type: <mime type>".

**5. `lib/providers/app_providers.dart`**
- No changes needed — `openEditor` works via FileItem.type.

**6. `lib/constants/app_constants.dart`**
- Add holmes to the `FileExtensions` single-purpose list (new field):

```dart
  static const List<String> holmes = ['holmes'];
```

Or just leave this out — it is optional for this integration.

---

### pubspec.yaml changes

The `HolmesService` uses `dart:io`, `dart:typed_data` — all SDK. No new
dependencies needed.

---

### Verification after changes

1. Run `flutter pub get` in the editor directory.
2. Run `flutter analyze` — fix any analyzer issues.
3. Verify no compilation errors: `flutter build linux --debug` (or just
   `flutter analyze` since we're a vibecoder without full toolchain).
4. Commit the changes with message: `feat: add .holmes container format support`

---

### Important style rules

- All code comments are entirely in lowercase (existing code convention).
- Follow the existing style (2-space indent, trailing commas on multi-line
  argument lists, const constructors where possible).
- Do NOT refactor any existing working code — only add holmes-specific logic.
- Do NOT change the FileType enum or determineFileType — that ripples widely.
  Instead, use the `_buildHolmesIcon`, `_openHolmesFile`, and temp-extraction
  pattern described above.
- Holmes files display in the browser with `Icons.inbox` or a similar container
  icon; the details panel shows inner MIME type when known.
