#!/usr/bin/env python3
import os
import time
import subprocess
from pathlib import Path

WATCH_DIRS = [
    os.path.expanduser("~/DCIM"),
    os.path.expanduser("~/Download"),
    os.path.expanduser("~/Pictures"),
    os.path.expanduser("~/Movies"),
    os.path.expanduser("~/Music"),
]

def is_valid_holmes(filepath):
    try:
        with open(filepath, 'rb') as f:
            data = f.read(18)
            if len(data) < 18:
                return False
            if data[:6] != b'HOLMES':
                return False
            version = struct.unpack('>H', data[6:8])[0]
            if version != 1:
                return False
            mime_len = struct.unpack('>H', data[8:10])[0]
            if len(data) < 10 + mime_len + 8:
                return False
            return True
    except Exception:
        return False

def convert_file(filepath):
    # Use the holmes tool to convert the file in-place
    # We'll run the holmes command on the parent directory with --overwrite
    dirpath = os.path.dirname(filepath)
    try:
        subprocess.run([
            'python3', '/home/house/projects/holmes/core/bin/holmes.py',
            dirpath, '--overwrite'
        ], check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        print(f"Conversion failed for {filepath}: {e.stderr}")

def main():
    # Use inotifywait to monitor events
    # We'll watch for CLOSE_WRITE and MOVED_TO on *.holmes files
    # Build the inotifywait command
    cmd = ['inotifywait', '-m', '-r', '-e', 'close_write,moved_to',
           '--format', '%w%f'] + WATCH_DIRS
    print(f"Starting Holmes watcher on: {WATCH_DIRS}")
    print(f"Command: {' '.join(cmd)}")
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    for line in proc.stdout:
        filepath = line.strip()
        if not filepath:
            continue
        if not filepath.endswith('.holmes', ignorecase=True):
            continue
        print(f"Event on {filepath}")
        if not is_valid_holmes(filepath):
            print(f"  -> Converting {filepath}")
            convert_file(filepath)
        else:
            print(f"  -> Already valid .holmes")

if __name__ == '__main__':
    import struct
    main()
