#!/usr/bin/env python3
"""
holmes — 3-in-1 media container format  (version 2)

binary layout:
  offset  length  field
  0       6       magic:    "HOLMES"
  6       2       version:  uint16 big-endian (currently 2)
  8       2       mime_len: uint16 big-endian = N
  10      N       mime string (ascii, validated against media whitelist)
  10+N   8       payload_len: uint64 big-endian = M
  10+N+12 4      crc32:    uint32 big-endian = CRC-32 of payload (IEEE 802.3)
  10+N+16 M       payload (raw original media bytes, zero alteration)

total header size: 18 + N + 8 + 4 = 30 + N bytes

version history:
  v1 (legacy): no CRC32, header = 18+N+8 bytes
  v2 (current): CRC32 after payload_len, header = 18+N+8+4 = 30+N bytes

all implementations SHOULD write v2. readers SHOULD accept both v1 (no CRC)
and v2 (with CRC) for backwards compatibility.
"""

import struct
import os
import sys
import argparse
import hashlib
import mimetypes as mime_module
from pathlib import Path
from typing import Optional

MAGIC = b'HOLMES'
VERSION = 2  # current spec version
LEGACY_VERSION = 1  # accepted for reading only

# ---------------------------------------------------------------------------
# validated media MIME whitelist
# any MIME not in this set is rejected at conversion time
# ---------------------------------------------------------------------------
ALLOWED_MIME_PREFIXES = ('image/', 'video/', 'audio/')

MEDIA_EXTENSIONS = {
    # images
    '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg', '.ico',
    '.tiff', '.tif', '.heic', '.heif', '.avif', '.raw', '.cr2', '.nef',
    '.arw', '.dng', '.psd', '.xcf',
    # video
    '.mp4', '.mov', '.avi', '.mkv', '.webm', '.flv', '.wmv', '.m4v',
    '.mpeg', '.mpg', '.3gp', '.3g2', '.ogv', '.ts', '.mts', '.m2ts',
    '.vob', '.divx', '.xvid',
    # audio
    '.mp3', '.wav', '.m4a', '.flac', '.ogg', '.aac', '.wma', '.aiff',
    '.aif', '.opus', '.ape', '.alac', '.mid', '.midi', '.pcm', '.dsd',
    '.dsf', '.dff', '.mka',
}


def is_media_extension(ext: str) -> bool:
    return ext.lower() in MEDIA_EXTENSIONS


def is_media_mime(mime: str) -> bool:
    return any(mime.startswith(p) for p in ALLOWED_MIME_PREFIXES)


def validate_mime(mime: str) -> None:
    """Raise ValueError if mime is not in the media whitelist."""
    if not is_media_mime(mime):
        raise ValueError(
            f"MIME type '{mime}' is not a recognised media type. "
            f"Only {', '.join(ALLOWED_MIME_PREFIXES)} are allowed."
        )


def detect_mime(filepath: str) -> str:
    """Detect MIME using `file --mime-type`, falling back to Python mimetypes."""
    try:
        result = __import__('subprocess').run(
            ['file', '--mime-type', '-b', filepath],
            capture_output=True, text=True, timeout=5
        )
        mime = result.stdout.strip().splitlines()[0].strip()
        if mime and mime != 'application/octet-stream':
            return mime
    except (FileNotFoundError, __import__('subprocess').TimeoutExpired):
        pass
    mime, _ = mime_module.guess_type(filepath)
    return mime or 'application/octet-stream'


def crc32(data: bytes) -> int:
    """CRC-32 (IEEE 802.3 / ZIP / PNG polynomial)."""
    return 0xFFFFFFFF & (zlib := __import__('zlib').crc32(data))


# ---------------------------------------------------------------------------
# binary header helpers
# ---------------------------------------------------------------------------

def make_header(mime_str: str, payload_len: int, legacy: bool = False) -> bytes:
    """Build a v2 header (with CRC32 placeholder, filled after payload is known).

    When legacy=True the CRC32 field is zeroed for backwards-compat writers.
    """
    mime_bytes = mime_str.encode('ascii')
    if len(mime_bytes) > 65535:
        raise ValueError(f'MIME string too long ({len(mime_bytes)} bytes): {mime_str}')

    header = MAGIC                                     # 6
    header += struct.pack('>H', VERSION)              # 2
    header += struct.pack('>H', len(mime_bytes))       # 2
    header += mime_bytes                               # N
    header += struct.pack('>Q', payload_len)          # 8
    if not legacy:
        header += struct.pack('>I', 0)                # 4  CRC32 placeholder
    return header


def make_header_with_crc(mime_str: str, payload: bytes, legacy: bool = False) -> bytes:
    """Build a complete header including CRC32 of payload."""
    header = make_header(mime_str, len(payload), legacy=legacy)
    if not legacy:
        checksum = crc32(payload)
        # replace the last 4 bytes (CRC placeholder) with the real CRC
        header = header[:-4] + struct.pack('>I', checksum)
    return header


def parse_header(data: bytes) -> dict:
    """Parse a holmes header. Accepts both v1 (no CRC) and v2 (CRC present)."""
    if len(data) < 18:
        raise ValueError('file too small to contain a holmes header (< 18 bytes)')
    if data[:6] != MAGIC:
        raise ValueError('not a holmes file (bad magic bytes)')
    if len(data) < 10:
        raise ValueError('file truncated — missing version/mime_len')

    version = struct.unpack('>H', data[6:8])[0]
    mime_len = struct.unpack('>H', data[8:10])[0]

    if len(data) < 10 + mime_len + 8:
        raise ValueError(
            f'file truncated — expected at least {10 + mime_len + 8} bytes, got {len(data)}'
        )
    mime_str = data[10:10 + mime_len].decode('ascii', errors='replace')
    payload_len = struct.unpack('>Q', data[10 + mime_len:10 + mime_len + 8])[0]

    if version == 2 and len(data) >= 10 + mime_len + 8 + 4:
        has_crc = True
        crc_stored = struct.unpack('>I', data[10 + mime_len + 8:10 + mime_len + 12])[0]
    else:
        has_crc = False
        crc_stored = None

    payload_start = 10 + mime_len + 8 + (4 if has_crc else 0)
    return {
        'version': version,
        'mime_type': mime_str,
        'mime_len': mime_len,
        'payload_len': payload_len,
        'payload_start': payload_start,
        'has_crc': has_crc,
        'crc_stored': crc_stored,
    }


def verify_crc(data: bytes, header: dict) -> bool:
    """Verify the CRC32 of the embedded payload, if present."""
    if not header['has_crc'] or header['crc_stored'] is None:
        return True  # v1 has no CRC, treat as pass
    start = header['payload_start']
    end = start + header['payload_len']
    if end > len(data):
        return False
    payload = data[start:end]
    return crc32(payload) == header['crc_stored']


# ---------------------------------------------------------------------------
# MIME → extension mapping
# ---------------------------------------------------------------------------

MIME_TO_EXT = {
    'image/jpeg': '.jpg', 'image/png': '.png', 'image/gif': '.gif',
    'image/webp': '.webp', 'image/bmp': '.bmp', 'image/svg+xml': '.svg',
    'image/x-icon': '.ico', 'image/tiff': '.tiff',
    'video/mp4': '.mp4', 'video/quicktime': '.mov', 'video/x-msvideo': '.avi',
    'video/x-matroska': '.mkv', 'video/webm': '.webm', 'video/x-flv': '.flv',
    'video/x-ms-wmv': '.wmv', 'video/x-m4v': '.m4v', 'video/mpeg': '.mpeg',
    'video/3gpp': '.3gp',
    'audio/mpeg': '.mp3', 'audio/wav': '.wav', 'audio/x-m4a': '.m4a',
    'audio/mp4': '.m4a', 'audio/flac': '.flac', 'audio/ogg': '.ogg',
    'audio/aac': '.aac', 'audio/x-wma': '.wma', 'audio/x-aiff': '.aiff',
    'audio/opus': '.opus',
}


def mime_to_extension(mime: str) -> str:
    if mime in MIME_TO_EXT:
        return MIME_TO_EXT[mime]
    guessed = mime_module.guess_extension(mime, strict=False)
    if guessed:
        return guessed
    # strip x- prefix and retry
    guessed = mime_module.guess_extension(mime.replace('x-', ''), strict=False)
    return guessed if guessed else '.bin'


# ---------------------------------------------------------------------------
# conversion
# ---------------------------------------------------------------------------

def convert_file(src: Path, dst: Path, overwrite: bool = False) -> dict:
    """Convert a single media file to .holmes. Returns result dict."""
    ext = src.suffix.lower()
    if not is_media_extension(ext):
        return {'file': str(src), 'status': 'skipped', 'reason': 'not a media extension'}

    if dst.exists() and not overwrite:
        return {'file': str(src), 'status': 'skipped', 'reason': 'destination exists'}

    mime = detect_mime(str(src))
    validate_mime(mime)          # ← critique 3: whitelist enforcement
    payload = src.read_bytes()
    header = make_header_with_crc(mime, payload)
    dst.parent.mkdir(parents=True, exist_ok=True)
    with open(dst, 'wb') as f:
        f.write(header)
        f.write(payload)
    return {
        'file': str(src),
        'holmes': str(dst),
        'status': 'ok',
        'mime': mime,
        'size': len(payload),
        'overhead': len(header),
        'version': VERSION,
        'crc32': crc32(payload),
    }


def convert_folder(
    src_dir: Path,
    dst_dir: Optional[Path] = None,
    overwrite: bool = False,
    delete_originals: bool = False,
    verify: bool = True,
) -> dict:
    """Walk src_dir recursively and convert every media file to .holmes."""
    src_dir = src_dir.resolve()
    if dst_dir:
        dst_dir = dst_dir.resolve()
    else:
        dst_dir = src_dir

    results = {'ok': [], 'skipped': [], 'failed': [], 'total': 0, 'bytes_written': 0}

    for root, dirs, files in os.walk(src_dir):
        dirs.sort()
        for name in sorted(files):
            filepath = Path(root) / name
            ext = filepath.suffix.lower()
            if not is_media_extension(ext):
                continue

            rel = filepath.relative_to(src_dir)
            results['total'] += 1

            holmes_name = filepath.stem + '.holmes'
            if dst_dir != src_dir:
                out_path = dst_dir / rel.with_suffix('.holmes')
            else:
                out_path = filepath.with_suffix('.holmes')

            tmp_path = out_path.with_suffix('.holmes.part')
            try:
                result = convert_file(filepath, tmp_path, overwrite=True)
                if result['status'] != 'ok':
                    results['skipped'].append(result)
                    if tmp_path.exists():
                        tmp_path.unlink()
                    continue

                if verify and result.get('crc32') is not None:
                    # re-read and verify CRC
                    verify_data = tmp_path.read_bytes()
                    vheader = parse_header(verify_data)
                    if not verify_crc(verify_data, vheader):
                        raise ValueError(f'CRC verification failed for {tmp_path}')

                tmp_path.replace(out_path)
                results['ok'].append(result)
                results['bytes_written'] += result['size'] + result['overhead']

                if delete_originals:
                    filepath.unlink()

            except Exception as e:
                results['failed'].append({'file': str(filepath), 'error': str(e)})
                if tmp_path.exists():
                    tmp_path.unlink()

    return results


def print_summary(r: dict):
    print(f"\n{'=' * 50}")
    print("  holmes conversion complete")
    print(f"{'=' * 50}")
    print(f"  total files scanned : {r['total']}")
    print(f"  converted           : {len(r['ok'])}")
    print(f"  skipped             : {len(r['skipped'])}")
    print(f"  failed              : {len(r['failed'])}")
    mb = r['bytes_written'] / (1024 * 1024)
    print(f"  bytes written       : {r['bytes_written']:,} ({mb:.2f} mb)")
    print(f"{'=' * 50}\n")

    if r['ok']:
        print("  converted files:")
        for item in r['ok']:
            crc = item.get('crc32')
            crc_str = f"  crc=0x{crc:08x}" if crc is not None else ""
            print(f"    {item['holmes']}  ({item['mime']}, {item['size']:,} bytes){crc_str}")
    if r['failed']:
        print("  failed files:")
        for item in r['failed']:
            print(f"    {item['file']}: {item['error']}")


def main():
    epilog = """\
examples:
  %(prog)s ~/media                    convert a folder in-place
  %(prog)s ~/media -o ~/holmes/       convert to a separate output dir
  %(prog)s ~/media --delete           convert and delete originals (after verify)
  %(prog)s ~/media --overwrite         overwrite existing .holmes files
    """
    p = argparse.ArgumentParser(
        prog='holmes',
        description='batch-convert media files to .holmes 3-in-1 container format',
        epilog=epilog,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument('source', help='folder to convert (recursively)')
    p.add_argument('-o', '--output', help='output folder (default: in-place)')
    p.add_argument('--overwrite', action='store_true', help='overwrite existing .holmes files')
    p.add_argument('--delete', action='store_true', help='delete originals after conversion')
    p.add_argument('--no-verify', action='store_true', help='skip CRC verification step')
    p.add_argument('--legacy', action='store_true', help='write v1 format (no CRC32, for compatibility)')
    p.add_argument('--version', action='version', version='holmes 2.0.0')
    args = p.parse_args()

    global VERSION
    if args.legacy:
        VERSION = LEGACY_VERSION

    src = Path(args.source)
    if not src.is_dir():
        print(f'error: "{args.source}" is not a directory', file=sys.stderr)
        sys.exit(1)

    dst = Path(args.output) if args.output else None
    if dst:
        dst.mkdir(parents=True, exist_ok=True)

    ver_label = "v1 (legacy, no CRC)" if args.legacy else "v2 (CRC32)"
    print(f"holmes v{VERSION}.0.0 ({ver_label}) — converting media in: {src}")
    print(f"output: {'in-place' if not dst else dst}\n")

    r = convert_folder(
        src,
        dst_dir=dst,
        overwrite=args.overwrite,
        delete_originals=args.delete,
        verify=not args.no_verify,
    )
    print_summary(r)
    sys.exit(1 if r['failed'] else 0)


if __name__ == '__main__':
    main()
