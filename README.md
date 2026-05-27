<h1 align="center">holmes</h1>
<p align="center">
  <em>a robust, minimal implementation of a timeless idea</em>

  <br>
</p>

<hr>

<h2 align="center">what is .holmes?</h2>

<p align="center"><strong>.holmes</strong> is a minimal binary container for any media file. it wraps your
original file inside a small header that declares the mime type and length,
and (in v2) includes a crc-32 checksum to detect accidental corruption.
the payload is the exact original media file — zero transformation,
zero compression, zero encryption. all smarts live in the header.</p>

<pre align="center"><code>offset  size  field
0       6     magic:        "HOLMES"
6       2     version:      uint16 (big-endian)   ← 1 = legacy, 2 = current
8       2     mime_len:     uint16 (big-endian)
10      n     mime:         ascii mime type (validated)
10+n    8     payload_len:  uint64 (big-endian)
10+n+12 4     crc32:        uint32 (big-endian, ieee 802.3)  ← v2 only
10+n+16 m     payload:      raw media bytes, length = payload_len
</code></pre>

header = 30 + n bytes, includes crc-32

<p align="center">all multi-byte integers are <strong>big-endian</strong>. the format is deliberately
minimal: one media file per container, no streaming, no multi-file support.</p>

<hr>

<h2 align="center">why .holmes?</h2>

<p align="center">file containers with routing headers are old and obvious:</p>
- tar (1979) puts a header at the front of each entry
- png/jpeg use structured headers that every decoder respects
- zip, xar, appimage, and many others prefix content with metadata

<p align="center">holmes applies that same principle to <strong>media serving and routing</strong>:
put the mime type (the routing signal) at the very start of the stream,
followed by the unaltered payload. a receiver can instantly know how to
handle the bytes without guessing from extensions, without consulting a
registry, and without scanning the file.</p>

<p align="center">this solves real‑world problems:</p>
- **extension mismatch**: `photo.jpg.holmes` has no extension that signals
its true content. standard tools need help — holmes-open provides it.
- **dark media buckets**: a folder of renamed files loses its routing
information. holmes restores it at byte zero.
- **integrity**: the optional crc-32 lets you detect corruption
(transmission errors, bit rot) before wasting time on a broken file.

<hr>

<h2 align="center">mime validation</h2>

<p align="center">unlike naïve formats that accept any bytes as a mime type, holmes <strong>validates</strong>
the mime string against a whitelist:</p>
- only mime types beginning with `image/`, `video/`, or `audio/` are allowed.
- this prevents wrapping of arbitrary file types and keeps the format focused
on media.

<p align="center">the header also includes a length-prefixed mime string (no null‑terminator),
avoiding ambiguity.</p>

<hr>

<h2 align="center">integrity checking</h2>

<p align="center">version 2 adds a <strong>crc-32 (ieee 802.3)</strong> of the payload, stored as a big-
endian <code>uint32</code> after the payload length. this lets you detect:</p>
- accidental corruption during transfer or storage
- truncation (if the file is shorter than expected)
- bit‑flips in the payload

<p align="center">the crc is <strong>not</strong> cryptographically secure; it is not meant to defend
against tampering, only against accidental errors.</p>

<hr>

<h2 align="center">repository layout</h2>

<pre align="center"><code>holmes/
├── holmes.py         batch converter (folder → .holmes)
├── holmes-extract    extract payload from a .holmes file
├── holmes-open       system handler (xdg-open integration)
├── holmes-info       inspect a .holmes header without extracting
├── spec/
│   ├── holmes_format.h   c header with binary layout & helpers
│   └── spec.md           full format specification
└── tests/
    └── test_holmes.py   python test suite
</code></pre>

<hr>

<h2 align="center">usage</h2>

<pre align="center"><code># convert a folder of media to .holmes (v2, with crc)
python3 holmes.py ~/my-photos/
# extract a single file
python3 holmes-extract photo.holmes output.jpg
# inspect a .holmes file without extracting
python3 holmes-info photo.holmes
</code></pre>

<hr>

<h2 align="center">license</h2>

<p align="center"><a href="LICENSE">mit</a></p>
