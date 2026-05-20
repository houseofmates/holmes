<h1 align="center">holmes</h1>

<p align="center">
  a self-describing media container format
  <br>
  <em>a robust, minimal implementation of a timeless idea</em>
</p>

---

## what is .holmes?

**.holmes** is a minimal binary container for any media file. It wraps your
original file inside a small header that declares the MIME type and length,
and (in v2) includes a CRC-32 checksum to detect accidental corruption.

The payload is the exact original media file — zero transformation,
zero compression, zero encryption. All smarts live in the header.

```
offset  size  field
0       6     magic:          "HOLMES"
6       2     version:        uint16 (big-endian)   ← 1 = legacy, 2 = current
8       2     mime_len:       uint16 (big-endian)
10      N     mime:           ASCII MIME type (validated)
10+N    8     payload_len:    uint64 (big-endian)
10+N+12 4     crc32:          uint32 (big-endian, IEEE 802.3)  ← v2 only
10+N+16 M     payload:        raw media bytes, length = payload_len
```

- **v1** (legacy): header = 18 + N bytes, no CRC-32 field  
- **v2** (current): header = 30 + N bytes, includes CRC-32

All multi-byte integers are **big-endian**. The format is deliberately
minimal: one media file per container, no streaming, no multi-file support.

---

## why this format?

File containers with routing headers are old and obvious:  
- tar (1979) puts a header at the front of each entry  
- PNG/JPEG use structured headers that every decoder respects  
- ZIP, xar, AppImage, and many others prefix content with metadata  

Holmes applies that same principle to **media serving and routing**:  
put the MIME type (the routing signal) at the very start of the stream,
followed by the unaltered payload. A receiver can instantly know how to
handle the bytes without guessing from extensions, without consulting a
registry, and without scanning the file.

This solves real‑world problems:

- **Extension mismatch**: `photo.jpg.holmes` has no extension that signals
  its true content. Standard tools need help — holmes-open provides it.
- **Dark media buckets**: a folder of renamed files loses its routing
  information. Holmes restores it at byte zero.
- **Integrity**: the optional CRC-32 lets you detect corruption
  (transmission errors, bit rot) before wasting time on a broken file.

It’s not novel in principle, but it is **deliberately minimal** and
**practically useful**.

---

## validation & safety

Unlike naïve formats that accept any bytes as a MIME type, Holmes **validates**
the MIME string against a whitelist:

- Only MIME types beginning with `image/`, `video/`, or `audio/` are allowed.
- This prevents wrapping of arbitrary file types and keeps the format focused
  on media.

The header also includes a length-prefixed MIME string (no null‑terminator),
avoiding ambiguity.

---

## integrity checking (v2)

Version 2 adds a **CRC-32 (IEEE 802.3)** of the payload, stored as a big-
endian `uint32` after the payload length. This lets you detect:

- Accidental corruption during transfer or storage
- Truncation (if the file is shorter than expected)
- Bit‑flips in the payload

The CRC is **not** cryptographically secure; it is not meant to defend
against tampering, only against accidental errors.

Readers should accept both v1 (no CRC) and v2 (with CRC) for backward
compatibility. Writers are encouraged to use v2.

---

## endianness & portability

All integer fields (version, mime_len, payload_len, crc32) are stored in
**big‑endian (network) byte order**. This is the same order used by
IPv4/IPv6, TCP/UDP headers, PNG, JPEG, and many other formats.

Implementations on little‑endian systems must convert to/from host byte
order using the standard `htobe16/32/64` and `be16toh/32/64` functions (or
equivalent). The provided C header (`spec/holmes_format.h`) includes
helpers for this.

---

## scope

Holmes wraps **exactly one** media file per container. It is **not**
designed for:

- Multi‑file archives → use tar, zip, etc.
- Streaming with unknown length → use chunked transfer or other streaming
  formats
- Encryption or compression → apply those layers outside if needed

These are considered out of scope for v2. Future versions may introduce
extensions, but v2 stays focused on simplicity and robustness for the
single‑file use case.

---

## file layout

```
holmes/
├── holmes.py          batch converter (folder → .holmes)
├── holmes-extract     extract payload from a .holmes file
├── holmes-open        system handler (xdg-open integration)
├── holmes-info        inspect a .holmes header without extracting
├── spec/
│   ├── holmes_format.h   C header with binary layout & helpers
│   └── SPEC.md           full format specification (this document)
└── tests/
    └── test_holmes.py   Python test suite (roundtrip, CRC, errors)
```

Every tool is a single Python file with **zero third‑party dependencies**
in the core. The optional `file` command is used by the handler for
content detection when no HOLMES magic is present (renamed media files).

---

## usage

```bash
# convert a folder of media to .holmes (v2, with CRC)
python3 holmes.py ~/my-photos/

# convert and delete originals after verifying CRC
python3 holmes.py ~/archive/ --delete

# extract a single file
python3 holmes-extract photo.holmes output.jpg

# inspect a .holmes file without extracting
python3 holmes-info photo.holmes

# force legacy v1 output (no CRC) – useful for maximum compatibility
python3 holmes.py ~/data/ --legacy
```

---

## holmes-open – system handler

Double‑clicking a `.holmes` file (or selecting “Open With”) launches the
correct default application:

- `image/png` → eye of GNOME / image viewer
- `video/mp4` → VLC / default video player
- `audio/flac` → Rhythmbox / default audio player

**Renamed media files also work.** If a file lacks the HOLMES magic (e.g.
`photo.png` was renamed to `photo.holmes`), the handler detects the real
MIME type via the `file` command and opens the original file directly —
no conversion needed.

The handler is cross‑platform:

- Linux: uses `xdg-open`
- macOS: uses `open`
- Windows: uses `os.startfile`

It launches the application **non‑blocking** and cleans up any temporary
extracted files on exit.

See [`holmes-open`](holmes-open) for the implementation.

---

## test suite

Run the included test suite to verify roundtrip integrity, CRC
detection, MIME validation, and error handling:

```bash
python3 -m pytest tests/          # if pytest is available
# or
python3 tests/test_holmes.py
```

The tests cover:

- Roundtrip conversion (v2 and v1) – byte‑for‑byte identity
- CRC-32 injection and detection
- Rejection of non‑media MIME types
- Proper handling of renamed media files
- Header info output

---

## files

| file | purpose |
|---|---|
| `holmes.py` | batch converter (folder → .holmes) |
| `holmes-extract` | extract payload from a .holmes file |
| `holmes-open` | xdg-open / open / startfile handler with magic‑byte routing |
| `holmes-info` | print header info without extracting |
| `spec/holmes_format.h` | C header with binary layout and endianness helpers |
| `spec/SPEC.md` | full format specification (this document) |
| `tests/test_holmes.py` | Python test suite |

---

## license

MIT – see the LICENSE file.

---

*holmes: because sometimes the simplest idea — a header that says “this is what I am” — is all you need.*