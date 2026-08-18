#!/usr/bin/env python3
"""
holmes-test — end-to-end test for the holmes format + tools.
run from the holmes-project directory with: python3 tests/test_core.py
"""

import struct, os, random, sys, tempfile, shutil
from pathlib import Path

MAGIC = b'HOLMES'

# ── add parent "core/bin" to path so we can import the tool as a module ──
sys.path.insert(0, '/home/house/projects/holmes/core/bin')

from holmes import make_header, parse_header, is_media_file  # type: ignore


def make_holmes(mime: str, payload: bytes) -> bytes:
    return make_header(mime, len(payload)) + payload


def test_header_roundtrip():
    print("  · header roundtrip …", end=" ")
    header = make_header("image/jpeg", 12345)
    assert header[:6] == MAGIC
    assert struct.unpack('>H', header[6:8])[0] == 1
    mime_len = struct.unpack('>H', header[8:10])[0]
    assert header[10:10 + mime_len].decode() == "image/jpeg"
    payload_len = struct.unpack('>Q', header[10 + mime_len:10 + mime_len + 8])[0]
    assert payload_len == 12345
    print("ok")


def test_full_roundtrip():
    print("  · full encode/decode …", end=" ")
    fake_jpeg = os.urandom(1024 * 512)  # 512 kb of random data
    blob = make_holmes("video/mp4", fake_jpeg)
    info = parse_header(blob)
    assert info['mime_type'] == "video/mp4"
    assert info['payload_len'] == len(fake_jpeg)
    assert blob[info['payload_start']:] == fake_jpeg
    print("ok")


def test_corrupt_magic():
    print("  · corrupt magic detection …", end=" ")
    bad = b'BADMAG' + b'\x00' * 100
    try:
        parse_header(bad)
        print("FAIL — should have raised")
        return
    except ValueError:
        print("ok")


def test_truncation():
    print("  · truncation detection …", end=" ")
    # valid magic, version, short
    short = MAGIC + struct.pack('>H', 1) + struct.pack('>H', 4) + b'text'
    try:
        parse_header(short)
        print("FAIL — truncated file passed")
        return
    except ValueError:
        print("ok")


def test_batch_converter_smoke(tmp: Path):
    """create minimal real media files and run holmes convert."""
    print("  · batch converter smoke test …", end=" ")
    import subprocess

    media_dir = tmp / "media"
    out_dir = tmp / "holmes_out"
    media_dir.mkdir()

    # minimal valid 1×1 PNG (67 bytes)
    png_bytes = (
        b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01'
        b'\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89'
        b'\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01'
        b'\x0d\x0a\x2d\xb4\x00\x00\x00\x00IEND\xaeB`\x82'
    )
    # minimal valid MP3 frame (ID3v2 header + one frame, ~200 bytes)
    mp3_bytes = b'ID3\x03\x00\x00\x00\x00\x00\x00' + b'\xff' * 190
    # minimal viable webm container header
    webm_bytes = b'\x1a\x45\xdf\xa3' + os.urandom(300)

    for name, payload in [
        ("cat.png", png_bytes),
        ("song.mp3", mp3_bytes),
        ("clip.webm", webm_bytes),
    ]:
        f = media_dir / name
        f.write_bytes(payload)

    script = Path('/home/house/projects/holmes/core/bin/holmes')
    r = subprocess.run(
        [sys.executable, str(script), str(media_dir), '-o', str(out_dir)],
        capture_output=True, text=True, timeout=30
    )
    assert r.returncode == 0, f"holmes exited {r.returncode}\n{r.stderr}"

    holmes_files = list(out_dir.rglob("*.holmes"))
    assert len(holmes_files) == 3, f"expected 3 .holmes files, got {len(holmes_files)}"
    # find the right one
    assert len(holmes_files) == 3, f"expected 3 .holmes files, got {len(holmes_files)}: {holmes_files}"
    sample = [h for h in holmes_files if h.name == "clip.holmes"]
    assert sample, "did not find clip.holmes in holmes_files"
    sample_data = sample[0].read_bytes()
    info = parse_header(sample_data)
    assert info['mime_type'] in ('video/webm', 'application/octet-stream'), f"got {info['mime_type']}"
    print(f"ok — {len(holmes_files)} files converted")


def test_verify_tool(tmp: Path):
    print("  · holmes-verify …", end=" ")
    import subprocess
    script = Path('/home/house/projects/holmes/core/bin/holmes-verify')
    # create a valid .holmes
    tmp_h = tmp / "valid.holmes"
    tmp_h.write_bytes(make_holmes("image/png", b'\x89PNG\r\n\x1a\n' + os.urandom(64)))
    r = subprocess.run([sys.executable, str(script), str(tmp_h)], capture_output=True, text=True, timeout=10)
    assert r.returncode == 0, f"verify failed:\n{r.stdout}\n{r.stderr}"
    # corrupt one
    tmp_bad = tmp / "bad.holmes"
    tmp_bad.write_bytes(b'CORRUPT' + os.urandom(100))
    r2 = subprocess.run([sys.executable, str(script), str(tmp_bad)], capture_output=True, text=True, timeout=10)
    assert r2.returncode == 1, "verify should have rejected corrupt file"
    print("ok")


def test_extract_tool(tmp: Path):
    print("  · holmes-extract …", end=" ")
    import subprocess
    original = os.urandom(4096)
    blob = make_holmes("audio/wav", original)
    holmes_path = tmp / "sound.holmes"
    holmes_path.write_bytes(blob)
    out_path = tmp / "sound.wav"
    script = Path('/home/house/projects/holmes/core/bin/holmes-extract')
    r = subprocess.run(
        [sys.executable, str(script), str(holmes_path), str(out_path)],
        capture_output=True, text=True, timeout=10
    )
    assert r.returncode == 0, f"extract failed:\n{r.stderr}"
    assert out_path.read_bytes() == original, "extracted payload does not match"
    print("ok")


def test_media_extension_detection():
    print("  · media extension detection …", end=" ")
    for good in ["jpg", "mp4", "mp3", "flac", "mov", "gif"]:
        assert is_media_file(f".{good}")
    assert not is_media_file(".txt")
    assert not is_media_file(".py")
    print("ok")


def test_no_holmes_conflict():
    print("  · no .holmes in media set …", end=" ")
    assert not is_media_file(".holmes"), "holmes extension must NOT be in media set"
    print("ok")


def run(tmp: Path):
    os.makedirs(tmp, exist_ok=True)
    print("\n── holmes core tests ──────────────────────────────")
    tests_noargs = [
        ("header roundtrip",        test_header_roundtrip),
        ("full encode/decode",       test_full_roundtrip),
        ("corrupt magic detection",  test_corrupt_magic),
        ("truncation detection",     test_truncation),
        ("media extension detection",test_media_extension_detection),
        ("no holmes in media set",   test_no_holmes_conflict),
    ]
    tests_withtmp = [
        ("batch converter smoke",    lambda: test_batch_converter_smoke(tmp)),
        ("holmes-verify",            lambda: test_verify_tool(tmp)),
        ("holmes-extract",           lambda: test_extract_tool(tmp)),
    ]
    for name, t in tests_noargs:
        try:
            t()
            print(f"  · {name} ... ok")
        except Exception as e:
            print(f"\n  ✗ {name}: {e}")
            raise
    for name, t in tests_withtmp:
        try:
            t()
            print(f"  · {name} ... ok")
        except Exception as e:
            print(f"\n  ✗ {name}: {e}")
            raise
    print("── all tests passed ───────────────────────────────\n")


if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='holmes-test-') as td:
        run(Path(td))
