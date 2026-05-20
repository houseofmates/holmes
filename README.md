<h1 align="center">holmes</h1>

<p align="center">
  a self-describing media container format
  <br>
  <em>a robust, minimal implementation of a timeless idea</em>
</p>

---

<h2 align="center">what is .holmes?</h2>

**.holmes** is a minimal binary container for any media file. it wraps your
original file inside a small header that declares the mime type and length,
and (in v2) includes a crc-32 checksum to detect accidental corruption.

the payload is the exact original media file — zero transformation,
zero compression, zero encryption. all smarts live in the header.

```text
offset  size  field
0       6     magic:        "HOLMES"
6       2     version:      uint16 (big-endian)   ← 1 = legacy, 2 = current
8       2     mime_len:     uint16 (big-endian)
10      n     mime:         ascii mime type (validated)
10+n    8     payload_len:  uint64 (big-endian)
10+n+12 4     crc32:        uint32 (big-endian, ieee 802.3)  ← v2 only
10+n+16 m     payload:      raw media bytes, length = payload_len

```

* **v1** (legacy): header = 18 + n bytes, no crc-32 field
* **v2** (current): header = 30 + n bytes, includes crc-32

all multi-byte integers are **big-endian**. the format is deliberately
minimal: one media file per container, no streaming, no multi-file support.

---

file containers with routing headers are old and obvious:

* tar (1979) puts a header at the front of each entry
* png/jpeg use structured headers that every decoder respects
* zip, xar, appimage, and many others prefix content with metadata

holmes applies that same principle to **media serving and routing**:

put the mime type (the routing signal) at the very start of the stream,
followed by the unaltered payload. a receiver can instantly know how to
handle the bytes without guessing from extensions, without consulting a
registry, and without scanning the file.

this solves real‑world problems:

* **extension mismatch**: `photo.jpg.holmes` has no extension that signals
its true content. standard tools need help — holmes-open provides it.
* **dark media buckets**: a folder of renamed files loses its routing
information. holmes restores it at byte zero.
* **integrity**: the optional crc-32 lets you detect corruption
(transmission errors, bit rot) before wasting time on a broken file.

---

unlike naïve formats that accept any bytes as a mime type, holmes **validates**
the mime string against a whitelist:

* only mime types beginning with `image/`, `video/`, or `audio/` are allowed.
* this prevents wrapping of arbitrary file types and keeps the format focused
on media.

the header also includes a length-prefixed mime string (no null‑terminator),
avoiding ambiguity.

---

version 2 adds a **crc-32 (ieee 802.3)** of the payload, stored as a big-
endian `uint32` after the payload length. this lets you detect:

* accidental corruption during transfer or storage
* truncation (if the file is shorter than expected)
* bit‑flips in the payload

the crc is **not** cryptographically secure; it is not meant to defend
against tampering, only against accidental errors.

---

```text
holmes/
├── holmes.py         batch converter (folder → .holmes)
├── holmes-extract    extract payload from a .holmes file
├── holmes-open       system handler (xdg-open integration)
├── holmes-info       inspect a .holmes header without extracting
├── spec/
│   ├── holmes_format.h   c header with binary layout & helpers
│   └── spec.md           full format specification
└── tests/
    └── test_holmes.py   python test suite

```

---

```bash
# convert a folder of media to .holmes (v2, with crc)
python3 holmes.py ~/my-photos/

# extract a single file
python3 holmes-extract photo.holmes output.jpg

# inspect a .holmes file without extracting
python3 holmes-info photo.holmes

```

---

mit – see the license file.

---

*holmes: because sometimes the simplest idea — a header that says “this is what i am” — is all you need.*

```
