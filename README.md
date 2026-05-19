<h1 align="center">holmes</h1>

<p align="center">
  a self-describing media container format
  <br>
  <em>a new take on an old, elegant idea</em>
</p>

---

## what is .holmes?

**.holmes** is a minimal binary container for any media file. it wraps your
original file inside a tiny 18+byte header — the file itself is untouched, just
prefixed with enough self-description that software downstream can act on it
intelligently without guessing, without extension checks, and without registry
entries.

```
offset  length  field
0       6       magic:    "HOLMES"
6       2       version:  uint16 big-endian (currently 1)
8       2       mime_len: uint16 big-endian = N
10      N       mime string (ascii)
10+N   8       payload_len: uint64 big-endian = M
10+N+8 M       payload (raw original media bytes, zero alteration)
```

that's it. the payload is the exact file you wrapped — bytes for byte, unmodified.
opening a .holmes is just: read 10+N+8 header bytes, then copy M bytes past
the end of the header.

---

## where does this idea come from?

file containers with routing headers are ancient and obvious — tar files have
their magic bytes at offset 0, PNG and JPEG use structured headers that every
decoder in the world respects, and formats like zip, xar, and appimage have been
doing exactly this for decades.

**.holmes** is a deliberate implementation of that same pattern but minimal —
focused specifically on media serving and routing. the header contains one
piece of routing intelligence: the MIME type of the payload. that is all the
routing information any smart consumer needs.

It's a "file router" in the same spirit as older routing formats: put the
instruction at the front of the stream and the content after, and let the
receiver act accordingly. nothing novel in principle, but deliberately minimal
in practice.

---

## convert and extract

```bash
# convert an entire folder of media to .holmes
python3 holmes.py ~/my-photos/

# extract a single .holmes file
python3 holmes-extract photo.holmes output.jpg

# convert and DELETE originals after verify
python3 holmes.py ~/archive/ --delete
```

---

## open .holmes files with the system handler

double-clicking a `.holmes` file opens it in the correct default application:

- `image/png` payload → eye of GNOME / image viewer
- `video/mp4` payload → VLC / default video player
- `audio/flac` payload → Rhythmbox / default audio player

**renamed media files also work.** if a file has no HOLMES header (e.g.
`photo.png` renamed to `photo.holmes`), the handler detects the real content
type via `file --mime-type` and opens it directly — no conversion needed.

see [`holmes-open`](holmes-open) for the system handler script.

---

## why bother?

because the real world is messier than ideal filesystems suggest:

- **extension mismatch:** "my-photo.jpg.holmes" has no extension to signal its
  content. standard file managers and applications need someone to step in —
  holmes-open fills that role.
- **dark media buckets:** a "media bucket" folder full of renamed files loses its
  routing information. holmes restores it at byte zero.
- **routing headers are timeless:** tar did it in 1979. PNG did it in 1996.
  appimage did it in 2008. holmes does it for media in 2025 with the simplest
  possible header — just enough to say "this is what I am."

---

## file layout

```
holmes/
├── holmes.py          batch converter (folder → .holmes)
├── holmes-extract     extract payload from a .holmes file
├── holmes-open        system handler (xdg-open integration)
└── holmes-info        inspect a .holmes header without extracting
```

Every tool in this repo is a single Python file. zero third-party dependencies
in the core tools. `file` command is the only optional external dependency for
content detection in the handler.

---

## license

MIT — do whatever you want with it.
