# Holmes Media Container Format Specification

## Status: Stable (v2.0.0)

## Overview

Holmes is a minimal binary container format for media files. It wraps any media file (image, video, audio) in a small header that describes the MIME type and length of the payload, allowing tools to route or process the file based on its actual content rather than relying on file extensions or external metadata.

The format is designed to be trivial to implement in any language, with a fixed binary layout and optional integrity checking.

## Binary Layout

All multi-byte integers are stored in **big-endian (network) byte order**.

### Version 2 (Current, with CRC-32)

| Offset | Size | Field          | Description |
|--------|------|----------------|-------------|
| 0      | 6    | magic          | ASCII string `"HOLMES"` |
| 6      | 2    | version        | `uint16` = 2 |
| 8      | 2    | mime_len       | `uint16` = length of MIME string in bytes |
| 10     | N    | mime           | ASCII MIME type (e.g., `"image/png"`), length = `mime_len` |
| 10+N   | 8    | payload_len    | `uint64` = length of payload in bytes |
| 10+N+8 | 4    | crc32          | `uint32` = CRC-32 (IEEE 802.3) of the payload |
| 10+N+12| M    | payload        | Raw media bytes, length = `payload_len` |

**Total header size**: 30 + N bytes

### Version 1 (Legacy, no CRC-32)

| Offset | Size | Field          | Description |
|--------|------|----------------|-------------|
| 0      | 6    | magic          | `"HOLMES"` |
| 6      | 2    | version        | `uint16` = 1 |
| 8      | 2    | mime_len       | `uint16` = length of MIME string |
| 10     | N    | mime           | ASCII MIME type |
| 10+N   | 8    | payload_len    | `uint64` = payload length |
| 10+N+8 | M    | payload        | Raw media bytes |

**Total header size**: 18 + N bytes

## Field Descriptions

### magic
Fixed ASCII string `"HOLMES"` (hex: 48 4F 4C 4D 45 53). Used to identify the file type.

### version
- `1`: Legacy format (no CRC-32 field)
- `2`: Current format (includes CRC-32)

### mime_len
Length of the MIME string in bytes, not including null terminator.

### mime
Null-termination is **not** used. The string is exactly `mime_len` bytes of ASCII data.
Only MIME types beginning with `image/`, `video/`, or `audio/` are considered valid.

### payload_len
Length of the payload in bytes. The payload is the original media file, unmodified.

### crc32 (v2 only)
CRC-32 of the payload, using the IEEE 802.3 polynomial (0xEDB88320), initial value 0xFFFFFFFF, final XOR 0xFFFFFFFF.
This field allows detection of accidental corruption.

### payload
The original media file, copied byte-for-byte. No transformation, compression, or encryption is applied.

## Endianness

All multi-byte integers (version, mime_len, payload_len, crc32) are stored in **big-endian** order.
Implementations on little-endian systems must convert to/from host byte order using `htobe16/32/64` and `be16toh/32/64` functions (or equivalent).

## Why Big-Endian?

Big-endian (network byte order) is the standard for many internet protocols and file formats (e.g., PNG, JPEG, TCP/IP headers). It ensures consistent interpretation across architectures without requiring the reader to know the writer's endianness.

## Scope

Holmes wraps **exactly one** media file per container. It is not designed for:
- Multi-file archives (use tar, zip, etc.)
- Streaming with unknown length (use chunked transfer or other streaming formats)
- Encryption or compression (apply those layers outside if needed)

These are considered out of scope for the core format. Future versions (v3) may introduce extensions for multi-part or streaming use cases, but v2 remains focused on simplicity and robustness for single-file wrapping.

## Integrity

The CRC-32 field in v2 provides protection against accidental corruption (e.g., transmission errors, storage bit rot). It is **not** cryptographically secure and should not be used for authentication or anti-tampering.

## MIME Validation

Only MIME types with prefixes `image/`, `video/`, or `audio/` are accepted. This prevents wrapping of arbitrary file types and keeps the format focused on media.

## Example

A PNG file (89 50 4E 47 0D 0A 1A 0A ...) with MIME type `"image/png"` (10 bytes) and size 100 bytes:

```
00 00 00 00 00 00 48 4F 4C 4D 45 53 00 02 00 0A 69 6D 61 67 65 2F 70 6E 67 00 00 00 00 00 00 00 64 <CRC> <100 bytes of PNG>
```

Breakdown:
- `48 4F 4C 4D 45 53` = "HOLMES"
- `00 02` = version 2
- `00 0A` = mime_len = 10
- `69 6D 61 67 65 2F 70 6E 67` = "image/png"
- `00 00 00 00 00 00 00 64` = payload_len = 100
- `<CRC>` = 4-byte CRC-32 of the 100-byte PNG payload
- `<100 bytes of PNG>` = the original PNG file, unmodified

## Implementations

The reference implementation is in Python (`holmes.py`, `holmes-extract`, `holmes-open`, `holmes-info`) and includes a C header file (`spec/holmes_format.h`) for systems programmers.

## License

MIT – see the LICENSE file in the repository.
