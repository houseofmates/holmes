"""
holmes-jellyfin-proxy  — transparent reverse proxy that un-wraps .holmes files
for Jellyfin playback without modifying Jellyfin itself.

how it works:
  jf-proxy listens on http://localhost:5050 and forwards everything to a
  real Jellyfin instance except .holmes file requests, which it intercepts,
  parses the header, and replies with only the inner media payload + the
  original MIME type.

setup:
  1. pip install flask requests
  2. export JELLYFIN_URL="http://your-jellyfin-server:8096"
  3. python3 holmes_jellyfin_proxy.py
  4. in Jellyfin → Dashboard → Libraries → Add REST API server:
     Base URL: http://<proxy-host>:5050  (and use this instead of Jellyfin directly)
"""

import struct
import os
import re
import sys
from pathlib import Path
from flask import Flask, request, Response, stream_with_context, abort
import requests

app = Flask(__name__)

MAGIC = b'HOLMES'
MIME_PATTERN = re.compile(r'[ -~]{1,255}')  # simple valid-mime match

# ─── configuration ────────────────────────────────────────────────────
JELLYFIN_URL = os.environ.get(
    'JELLYFIN_URL', 'http://localhost:8096'
)
HOLMES_CACHE_TTL = int(os.environ.get('HOLMES_CACHE_TTL', '3600'))  # seconds
# ──────────────────────────────────────────────────────────────────────


def parse_header(data: bytes):
    """return (mime_str, payload_offset) or raise ValueError."""
    if len(data) < 18 or data[:6] != MAGIC:
        raise ValueError('not a holmes file')
    mime_len = struct.unpack('>H', data[8:10])[0]
    if len(data) < 10 + mime_len + 8:
        raise ValueError('truncated holmes header')
    mime_str = data[10:10 + mime_len].decode('ascii', errors='replace')
    payload_start = 10 + mime_len + 8
    return mime_str, payload_start


def is_holmes_response(resp: requests.Response) -> bool:
    """check if the upstream Jellyfin response is actually a .holmes file."""
    content_type = resp.headers.get('Content-Type', '')
    # jf sometimes sends octet-stream but correct mime is elsewhere
    # we rely on Content-Disposition to detect filenames
    cd = resp.headers.get('Content-Disposition', '')
    is_holmes_dl = bool(re.search(r'\.holmes', cd, re.IGNORECASE))
    # also check the URL path
    is_holmes_url = bool(re.search(r'\.holmes(?:\?|$)', resp.request.url, re.IGNORECASE))
    return is_holmes_dl or is_holmes_url


def stream_holmes_payload(response: requests.Response, mime_str: str, payload_start: int):
    """yield holmes file bytes minus header, then pass through rest of stream."""
    remaining_to_skip = payload_start

    for chunk in response.iter_content(chunk_size=65536, decode_unicode=False):
        if remaining_to_skip > 0:
            if len(chunk) <= remaining_to_skip:
                remaining_to_skip -= len(chunk)
                continue
            # partial skip
            chunk = chunk[remaining_to_skip:]
            remaining_to_skip = 0

        yield chunk


@app.route('/health', methods=['GET'])
def health():
    return {'status': 'ok', 'jellyfin': JELLYFIN_URL, 'mode': 'holmes-proxy'}


@app.route('/', defaults={'path': ''}, methods=['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS'])
@app.route('/<path:path>', methods=['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS'])
def proxy(path: str):
    """main proxy handler — forward to Jellyfin, un-holmes .holmes responses."""
    target_url = f"{JELLYFIN_URL.rstrip('/')}/{path}"
    if request.query_string:
        target_url += f'?{request.query_string.decode()}'

    upstream_headers = {k: v for k, v in request.headers if k.lower() != 'host'}
    upstream_headers['Host'] = (
        JELLYFIN_URL.replace('http://', '')
                    .replace('https://', '')
                    .split('/')[0]
    )

    try:
        upstream_resp = requests.request(
            method=request.method,
            url=target_url,
            headers=upstream_headers,
            data=request.get_data() if request.method in ('POST', 'PUT', 'PATCH') else None,
            stream=True,
            timeout=120,
            # disable ssl verify for self-signed jf instances
            verify=os.environ.get('JELLYFIN_SSL_VERIFY', 'true').lower() != 'false',
        )
    except requests.RequestException as e:
        return {'error': f'upstream error: {e}'}, 502

    if not is_holmes_response(upstream_resp):
        # pass through — not a holmes file
        resp_headers = {
            k: v for k, v in upstream_resp.headers.items()
            if k.lower() not in ('transfer-encoding', 'connection')
        }
        return Response(
            stream_with_context(upstream_resp.iter_content()),
            status=upstream_resp.status_code,
            headers=resp_headers,
        )

    # ── holmes file path: parse header from first chunk ──────────────
    try:
        # we need at least enough for the header to parse
        first_bytes = upstream_resp.raw.read(65536)
        mime_str, payload_start = parse_header(first_bytes)

        def holmes_stream():
            # yield remainder of first chunk (after header), then rest
            if payload_start < len(first_bytes):
                yield first_bytes[payload_start:]
            else:
                # entire first chunk was header
                remaining_skip = payload_start - len(first_bytes)
                for chunk in upstream_resp.iter_content(chunk_size=65536, decode_unicode=False):
                    if remaining_skip > 0:
                        if len(chunk) <= remaining_skip:
                            remaining_skip -= len(chunk)
                            continue
                        chunk = chunk[remaining_skip:]
                        remaining_skip = 0
                    yield chunk

        content_type = mime_str if mime_str else 'application/octet-stream'
        cd = upstream_resp.headers.get('Content-Disposition', '')
        # strip .holmes from the filename in content-disposition
        cd_clean = re.sub(r'\.holmes(?=[\'";]|$)', '', cd, flags=re.IGNORECASE)
        resp_headers = {
            'Content-Type': content_type,
            'Content-Length': str(int(upstream_resp.headers.get('Content-Length', '0')) - payload_start),
        }
        if cd_clean:
            resp_headers['Content-Disposition'] = cd_clean

        return Response(
            stream_with_context(holmes_stream()),
            status=upstream_resp.status_code,
            headers=resp_headers,
        )

    except Exception as e:
        # fallback: pass raw response if header parsing fails
        print(f'[holmes-proxy] header parse failed: {e}', file=sys.stderr)
        resp_headers = {k: v for k, v in upstream_resp.headers.items()
                        if k.lower() not in ('transfer-encoding', 'connection')}
        return Response(
            stream_with_context(upstream_resp.iter_content()),
            status=upstream_resp.status_code,
            headers=resp_headers,
        )


if __name__ == '__main__':
    port = int(os.environ.get('HOLMES_PROXY_PORT', '5050'))
    print(f"holmes-jellyfin-proxy — forwarding to {JELLYFIN_URL}")
    print(f"  listening on http://localhost:{port}")
    print(f"  python requests version: {requests.__version__}")
    app.run(host='0.0.0.0', port=port, threaded=True)
