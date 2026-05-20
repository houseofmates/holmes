#!/usr/bin/env python3
"""
Minimal test suite for the holmes format.
"""
import os
import subprocess
import tempfile
import hashlib
import shutil

WORKDIR = '/tmp/holmes-work'
HOLMES_PY = os.path.join(WORKDIR, 'holmes.py')
HOLMES_EXTRACT = os.path.join(WORKDIR, 'holmes-extract')
HOLMES_OPEN = os.path.join(WORKDIR, 'holmes-open')
HOLMES_INFO = os.path.join(WORKDIR, 'holmes-info')

PNG_BYTES = bytes.fromhex(
    '89504e470d0a1a0a0000000d494844520000000100000001'
    '08060000001f15c4890000000a4944415478da6364'
    '60606060000000040001cd9d0f4b0000000049454e44ae426082'
)
PNG_SHA256 = hashlib.sha256(PNG_BYTES).hexdigest()

def run(cmd, input_data=None, cwd=None):
    proc = subprocess.run(
        cmd,
        input=input_data,
        capture_output=True,
        text=False,
        cwd=cwd,
    )
    return proc.returncode, proc.stdout, proc.stderr

def test_roundtrip_v2():
    with tempfile.TemporaryDirectory() as td:
        src_dir = os.path.join(td, 'src')
        os.makedirs(src_dir)
        src = os.path.join(src_dir, 'test.png')
        with open(src, 'wb') as f:
            f.write(PNG_BYTES)
        rc, out, err = run([HOLMES_PY, src_dir], cwd=WORKDIR)
        assert rc == 0, f'holmes.py failed: {err}'
        holmes = os.path.join(src_dir, 'test.holmes')
        assert os.path.exists(holmes), 'holmes file not created'
        rc, stdout_data, err = run([HOLMES_EXTRACT, holmes], cwd=WORKDIR)
        assert rc == 0, f'holmes-extract failed: {err}'
        assert stdout_data == PNG_BYTES, 'roundtrip data mismatch'
        assert hashlib.sha256(stdout_data).hexdigest() == PNG_SHA256, 'SHA mismatch'

def test_crc_detection():
    with tempfile.TemporaryDirectory() as td:
        src_dir = os.path.join(td, 'src')
        os.makedirs(src_dir)
        src = os.path.join(src_dir, 'test.png')
        with open(src, 'wb') as f:
            f.write(PNG_BYTES)
        rc, out, err = run([HOLMES_PY, src_dir], cwd=WORKDIR)
        assert rc == 0
        holmes = os.path.join(src_dir, 'test.holmes')
        # corrupt first byte of payload
        with open(holmes, 'r+b') as f:
            data = f.read()
            # header size: magic 6, version 2, mime_len 2, mime 9, payload_len 8, crc 4 = 31
            f.seek(31)
            b = f.read(1)
            f.seek(-1, 1)
            f.write(bytes([b[0] ^ 0xFF]))
        rc, out, err = run([HOLMES_EXTRACT, holmes], cwd=WORKDIR)
        assert rc != 0, 'expected extraction to fail due to CRC mismatch'
        err_lower = err.lower()
        assert b'crc' in err_lower or b'checksum' in err_lower, f'error does not mention CRC: {err}'

def test_renamed_media_handler():
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, 'image.png')
        with open(src, 'wb') as f:
            f.write(PNG_BYTES)
        holmes = os.path.join(td, 'image.holmes')
        shutil.copy2(src, holmes)
        rc, out, err = run([HOLMES_OPEN, holmes], cwd=WORKDIR)
        combined = out + err
        assert b'opened' in combined.lower(), f'expected opened message, got: {combined}'
        assert b'Traceback' not in combined, f'holmes-open crashed: {combined}'

def test_info_output():
    with tempfile.TemporaryDirectory() as td:
        src_dir = os.path.join(td, 'src')
        os.makedirs(src_dir)
        src = os.path.join(src_dir, 'test.png')
        with open(src, 'wb') as f:
            f.write(PNG_BYTES)
        rc, out, err = run([HOLMES_PY, src_dir], cwd=WORKDIR)
        assert rc == 0
        holmes = os.path.join(src_dir, 'test.holmes')
        rc, out, err = run([HOLMES_INFO, holmes], cwd=WORKDIR)
        assert rc == 0, f'holmes-info failed: {err}'
        out_lower = out.lower()
        assert b'version' in out_lower and b'mime' in out_lower, f'unexpected info output: {out}'

def main():
    test_roundtrip_v2()
    print('✓ roundtrip v2')
    test_crc_detection()
    print('✓ CRC detection')
    test_renamed_media_handler()
    print('✓ renamed media handler')
    test_info_output()
    print('✓ info output')
    print('All tests passed.')

if __name__ == '__main__':
    main()