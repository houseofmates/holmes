/*
 * holmes_format.h — binary layout definition for the holmes media container.
 *
 * This header defines the on-disk format for .holmes files, supporting both
 * version 1 (legacy, no integrity check) and version 2 (with CRC32).
 *
 * All integer fields are stored in big-endian (network) byte order.
 *
 * The format is intentionally minimal: a magic number, version, MIME length,
 * MIME string, payload length, optional CRC-32, and the raw payload.
 *
 * The payload is the original media file, unmodified.
 *
 * To write a holmes file:
 *   1. Determine the MIME type of the source file (must be image/*, video/*,
 *      or audio/*).
 *   2. Read the entire source file into memory.
 *   3. Compute the CRC-32 of the payload (if writing v2).
 *   4. Write the header as defined below, then write the payload.
 *
 * To read a holmes file:
 *   1. Verify the magic bytes "HOLMES".
 *   2. Read the version field.
 *   3. Read the MIME length and MIME string.
 *   4. Read the payload length.
 *   5. If version >= 2, read the CRC-32.
 *   6. Read exactly payload_len bytes as the payload.
 *   7. If version >= 2, verify the CRC-32 of the payload.
 *
 * The payload can then be used directly (e.g., passed to a media decoder).
 *
 * This format is designed to be easy to implement in any language.
 */
#ifndef HOLMES_FORMAT_H
#define HOLMES_FORMAT_H

#include <stdint.h>

/* Magic bytes: "HOLMES" */
#define HOLMES_MAGIC        0x484F4C4D4553ULL  /* "HOLMES" in ASCII, big-endian */

/* Current version of the format */
#define HOLMES_VERSION      2

/* Legacy version (no CRC-32) */
#define HOLMES_VERSION_LEGACY 1

/* Maximum allowed length of the MIME string (in bytes) */
#define HOLMES_MAX_MIME_LEN 65535

/* CRC-32 polynomial (IEEE 802.3) */
#define HOLMES_CRC32_POLY   0xEDB88320UL

/* Header layout for version 2:
 *
 *   offset  size  field
 *   0       6     magic:          "HOLMES"
 *   6       2     version:        uint16 (big-endian)
 *   8       2     mime_len:       uint16 (big-endian)
 *   10      N     mime:           ASCII string, length = mime_len
 *   10+N    8     payload_len:    uint64 (big-endian)
 *   10+N+8  4     crc32:          uint32 (big-endian), CRC-32 of payload
 *   10+N+12 M     payload:        raw media bytes, length = payload_len
 *
 * Total header size (v2): 6 + 2 + 2 + N + 8 + 4 = 22 + N bytes
 *
 * For version 1 (legacy), the CRC-32 field is absent:
 *
 *   offset  size  field
 *   0       6     magic:          "HOLMES"
 *   6       2     version:        uint16 (big-endian)
 *   8       2     mime_len:       uint16 (big-endian)
 *   10      N     mime:           ASCII string, length = mime_len
 *   10+N    8     payload_len:    uint64 (big-endian)
 *   10+N+8  M     payload:        raw media bytes, length = payload_len
 *
 * Total header size (v1): 6 + 2 + 2 + N + 8 = 18 + N bytes
 */

/* Helper macros for endianness conversion (assuming host may be little- or big-endian) */
#if defined(__BYTE_ORDER__) && defined(__ORDER_LITTLE_ENDIAN__)
#  if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#    define htobe16(x) (__builtin_bswap16(x))
#    define htobe32(x) (__builtin_bswap32(x))
#    define htobe64(x) (__builtin_bswap64(x))
#    define be16toh(x) (__builtin_bswap16(x))
#    define be32toh(x) (__builtin_bswap32(x))
#    define be64toh(x) (__builtin_bswap64(x))
#  else
/* big-endian host */
#    define htobe16(x) (x)
#    define htobe32(x) (x)
#    define htobe64(x) (x)
#    define be16toh(x) (x)
#    define be32toh(x) (x)
#    define be64toh(x) (x)
#  endif
#else
/* Fallback: implement manually */
static inline uint16_t htobe16(uint16_t x) {
    return (uint16_t)((x >> 8) | (x << 8));
}
static inline uint32_t htobe32(uint32_t x) {
    return ((x >> 24) & 0xFF) |
           ((x >> 8) & 0xFF00) |
           ((x << 8) & 0xFF0000) |
           ((x << 24) & 0xFF000000);
}
static inline uint64_t htobe64(uint64_t x) {
    return ((x >> 56) & 0xFF) |
           ((x >> 48) & 0xFF00) |
           ((x >> 40) & 0xFF0000) |
           ((x >> 32) & 0xFF000000) |
           ((x >> 24) & 0xFF0000000) |
           ((x >> 16) & 0xFF00000000) |
           ((x >> 8) & 0xFF000000000) |
           ((x << 8) & 0xFF0000000000);
}
static inline uint16_t be16toh(uint16_t x) { return htobe16(x); }
static inline uint32_t be32toh(uint32_t x) { return htobe32(x); }
static inline uint64_t be64toh(uint64_t x) { return htobe64(x); }
#endif

/* CRC-32 calculation (IEEE 802.3) */
static inline uint32_t holmes_crc32(const uint8_t *data, size_t len) {
    uint32_t crc = 0xFFFFFFFF;
    for (size_t i = 0; i < len; ++i) {
        crc = (crc >> 8) ^ HOLMES_CRC32_POLY[(crc ^ data[i]) & 0xFF];
    }
    return ~crc;
}

/* Validate that a MIME string is within the allowed media types.
 * Returns 0 if valid, -1 if not.
 */
static inline int holmes_mime_valid(const char *mime) {
    /* Allowed prefixes: image/, video/, audio/ */
    if (strncmp(mime, "image/", 6) == 0 ||
        strncmp(mime, "video/", 6) == 0 ||
        strncmp(mime, "audio/", 6) == 0) {
        return 0;
    }
    return -1;
}

#endif /* HOLMES_FORMAT_H */