#!/usr/bin/env python3
"""
holmes - 3-in-1 media container format

binary layout:
  offset  length  field
  0       6       magic: "HOLMES"
  6       2       version: uint16 big-endian (currently 1)
  8       2       mime_len: uint16 big-endian = N
  10      N       mime string (ascii)
  10+N   8       payload_len: uint64 big-endian = M
  10+N+8 M       payload (raw original media bytes, untouched)

total overhead to extract payload: read first 18+N+8 bytes, skip to 10+N+8,
then copy M bytes. with dd: dd if=<file> bs=1 skip=<18+N+8>
"""

import struct
import os
import sys
import argparse
import mimetypes as mime_module
from pathlib import Path
from typing import Optional

MAGIC = b'HOLMES'
VERSION = 1  # uint16 be

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


def detect_mime(filepath: str) -> str:
    """detect mime type using `file` command, falling back to python mimetypes."""
    import subprocess

    # 1) try `file --mime-type` — catches compressed formats (.gz, .xz, etc.)
    try:
        result = subprocess.run(
            ['file', '--mime-type', '-b', filepath],
            capture_output=True, text=True, timeout=5
        )
        mime = result.stdout.strip().split('\n')[0].strip()
        if mime and mime != 'application/octet-stream':
            return mime
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    # 2) python mimetypes — good for known extensions
    mime, _ = mime_module.guess_type(filepath)
    if mime:
        return mime

    return 'application/octet-stream'


def make_header(mime_str: str, payload_len: int) -> bytes:
    """build the binary holmes header (without payload)."""
    mime_bytes = mime_str.encode('ascii')
    if len(mime_bytes) > 65535:
        raise ValueError(f'mime string too long ({len(mime_bytes)} bytes): {mime_str}')
    header = MAGIC                                     # 6
    header += struct.pack('>H', VERSION)              # 2
    header += struct.pack('>H', len(mime_bytes))       # 2
    header += mime_bytes                               # N
    header += struct.pack('>Q', payload_len)          # 8
    return header


def parse_header(data: bytes) -> dict:
    """parse a holmes header from bytes. raises ValueError on bad data."""
    if len(data) < 18:
        raise ValueError('file too small to contain a holmes header (< 18 bytes)')
    if data[:6] != MAGIC:
        raise ValueError('not a holmes file (bad magic bytes)')
    if len(data) < 10:
        raise ValueError('file truncated — missing version/mime_len')
    version = struct.unpack('>H', data[6:8])[0]
    mime_len = struct.unpack('>H', data[8:10])[0]
    if len(data) < 10 + mime_len + 8:
        raise ValueError(f'file truncated — expected at least {10 + mime_len + 8} bytes, got {len(data)}')
    mime_str = data[10:10 + mime_len].decode('ascii', errors='replace')
    payload_len = struct.unpack('>Q', data[10 + mime_len:10 + mime_len + 8])[0]
    return {
        'version': version,
        'mime_type': mime_str,
        'mime_len': mime_len,
        'payload_len': payload_len,
        'payload_start': 10 + mime_len + 8,
    }


def is_media_file(ext: str) -> bool:
    return ext.lower() in MEDIA_EXTENSIONS


def convert_file(src: Path, dst: Path, overwrite: bool = False) -> dict:
    """convert a single media file to .holmes. returns result dict."""
    ext = src.suffix.lower()
    if not is_media_file(ext):
        return {'file': str(src), 'status': 'skipped', 'reason': 'not a media extension'}

    if dst.exists():
        if not overwrite:
            return {'file': str(src), 'status': 'skipped', 'reason': 'destination exists'}

    mime = detect_mime(str(src))
    payload = src.read_bytes()
    header = make_header(mime, len(payload))
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
    }


def convert_folder(
    src_dir: Path,
    dst_dir: Optional[Path] = None,
    overwrite: bool = False,
    delete_originals: bool = False,
    verify: bool = True,
) -> dict:
    """
    walk src_dir recursively and convert every media file to .holmes.

    if dst_dir is given, write .holmes there mirroring directory structure.
    if dst_dir is None, replace originals with .holmes in-place (dangerous).
    """
    src_dir = src_dir.resolve()
    if dst_dir:
        dst_dir = dst_dir.resolve()
    else:
        dst_dir = src_dir  # in-place: .holmes goes next to the original

    results = {'ok': [], 'skipped': [], 'failed': [], 'total': 0, 'bytes_written': 0}

    for root, dirs, files in os.walk(src_dir):
        dirs.sort()
        for name in sorted(files):
            filepath = Path(root) / name
            ext = filepath.suffix.lower()
            if not is_media_file(ext):
                continue

            rel = filepath.relative_to(src_dir)
            results['total'] += 1

            holmes_name = filepath.stem + '.holmes'
            if dst_dir != src_dir:
                # preserve directory structure under dst_dir
                out_path = dst_dir / rel.with_suffix('.holmes')
            else:
                # in-place: .holmes goes in the same folder
                out_path = filepath.with_suffix('.holmes')

            # in-place mode safety: write to temp first, then atomically rename
            tmp_path = out_path.with_suffix('.holmes.part')
            try:
                result = convert_file(filepath, tmp_path, overwrite=True)
                if result['status'] != 'ok':
                    results['skipped'].append(result)
                    if tmp_path.exists():
                        tmp_path.unlink()
                    continue

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
    print(f"\n{'='*50}")
    print(f"  holmes conversion complete")
    print(f"{'='*50}")
    print(f"  total files scanned : {r['total']}")
    print(f"  converted           : {len(r['ok'])}")
    print(f"  skipped             : {len(r['skipped'])}")
    print(f"  failed              : {len(r['failed'])}")
    mb = r['bytes_written'] / (1024 * 1024)
    print(f"  bytes written       : {r['bytes_written']:,} ({mb:.2f} mb)")
    print(f"{'='*50}\n")

    if r['ok']:
        print("  converted files:")
        for item in r['ok']:
            print(f"    {item['holmes']}  ({item['mime']}, {item['size']:,} bytes)")
    if r['failed']:
        print("  failed files:")
        for item in r['failed']:
            print(f"    {item['file']}: {item['error']}")


def main():
    epilog = """
examples:
  %(prog)s ~/media                    convert a folder in-place
  %(prog)s ~/media -o ~/holmes/       convert to a separate output dir
  %(prog)s ~/media --delete            convert and delete originals (after verify)
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
    p.add_argument('--no-verify', action='store_true', help='skip verify step (only with --delete)')
    p.add_argument('--version', action='version', version='holmes 1.0.0')
    args = p.parse_args()

    src = Path(args.source)
    if not src.is_dir():
        print(f'error: "{args.source}" is not a directory', file=sys.stderr)
        sys.exit(1)

    dst = Path(args.output) if args.output else None
    if dst:
        dst.mkdir(parents=True, exist_ok=True)

    print(f"holmes v1.0.0 — converting media in: {src}")
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
