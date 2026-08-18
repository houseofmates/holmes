<h1 align="center">holmes — 3-in-1 media container format</h1>


a simple binary wrapper around any media file (image, video, or audio).
the original file is stored verbatim inside, along with a small header that
tells any consumer _exactly_ what it is. no re-encoding, no quality loss,
zero dependencies on the system — just `dd` or a python script to get the
original back.

```
┌─ holmes file ───────────────────────────────────────────┐
│ magic (6)    "holmes"                                    │
│ version (2)  0x0001                                      │
│ mime_len (2) n                                           │
│ mime (n)     e.g. "video/mp4"                            │
│ length (8)   m                                           │
│ payload (m)  ← raw original media, untouched             │
└──────────────────────────────────────────────────────────┘
```

total header overhead: **18 + len(mime)** bytes.

---

<h2 align="center">1. run the converter</h2>


```bash
<h1 align="center">install python deps (only python stdlib + `file` command needed)</h1>

sudo apt install file  # on most linux distros, file is already installed

<h1 align="center">clone / make executable</h1>

cd ~/holmes-project/core/bin
chmod +x holmes holmes-extract holmes-verify holmes-info

<h1 align="center">convert a folder in-place (replaces original with .holmes)</h1>

~/holmes-project/core/bin/holmes ~/pictures

<h1 align="center">or convert to a separate output folder (keeps originals)</h1>

~/holmes-project/core/bin/holmes ~/videos -o ~/holmes_videos

<h1 align="center">with progress and summary</h1>

~/holmes-project/core/bin/holmes ~/music --overwrite
```

<h3 align="center">four companion tools</h3>


```bash
<h1 align="center">show info about a .holmes file</h1>

~/holmes-project/core/bin/holmes-info ~/holmes_videos/clip.holmes

<h1 align="center">extract the inner media (override output name if you want)</h1>

~/holmes-project/core/bin/holmes-extract ~/holmes_videos/clip.holmes clip.mp4

<h1 align="center">verify a .holmes file is well-formed</h1>

~/holmes-project/core/bin/holmes-verify ~/holmes_videos/clip.holmes

<h1 align="center">runs the full python test suite</h1>

cd ~/holmes-project && pythonpath=core/bin python3 core/tests/test_core.py
```

---

<h2 align="center">2. open .holmes files in the editor</h2>


<h3 align="center">editor changes applied</h3>


commit `feat: add .holmes container format support` on the `fix/review-improvements`
branch of `https://github.com/houseofmates/editor`.

```bash
cd ~/editor
git pull origin fix/review-improvements

<h1 align="center">build (flutter sdk at ~/flutter-sdk)</h1>

export path="$home/flutter-sdk/bin:$path"
flutter clean && flutter build linux --release --no-tree-shake-icons
bash build_deb.sh
<h1 align="center">build & install the patched editor:</h1>

<h1 align="center">cd ~/editor && export path="$home/flutter-sdk/bin:$path"</h1>

<h1 align="center">flutter build linux --release --no-tree-shake-icons</h1>

<h1 align="center">bash build_deb.sh && sudo dpkg -i releases/editor_1.0.0_amd64.deb  # check actual .deb name</h1>

```

**what happens when you open a .holmes file:**

1. the header is parsed instantly to discover the inner mime type
2. the payload is extracted to a temp file in `xdg_cache`
3. the appropriate editor tab (image / video / audio) is opened with the temp file
4. when you close the tab the temp file is cleaned up

in the file browser:
- .holmes files show an `inbox` icon (blue accent colour)
- the details panel shows `inner type: video/mp4` instead of generic "other"
- double-clicking one opens it in the correct editor

<h3 align="center">.android note</h3>


the holmes logic in `browser_screen.dart` runs on all platforms (linux + android).
the `extracttotemp()` method uses `path_provider` which uses `gettemporarydirectory()`
which maps to `/data/data/<package>/cache/` on android.

---

<h2 align="center">3. jellyfin — holmes proxy</h2>


<h3 align="center">the problem</h3>


jellyfin uses `ffprobe` to read media headers. `ffprobe` does not understand
the .holmes wrapper, so .holmes files show as "unknown type" in jellyfin even
after they are indexed.

<h3 align="center">the solution: a transparent reverse proxy</h3>


run a tiny flask proxy between jellyfin and your browser / clients:

```bash
cd ~/holmes-project/jellyfin

<h1 align="center">one-time install</h1>

pip3 install --user flask requests

<h1 align="center">set your real jellyfin url</h1>

export jellyfin_url="http://localhost:8096"   # or your remote jellyfin

<h1 align="center">start it</h1>

python3 ~/holmes-project/jellyfin/holmes_jellyfin_proxy.py
```

the proxy listens on `http://localhost:5050`.

**how to use it:**

- point your jellyfin client (browser, mobile app, etc.) at **http://localhost:5050**
  instead of the normal jellyfin url
- the proxy forwards everything transparently, except for `.holmes` file
  responses — those are transparently un-wrapped and streamed with the
  correct `content-type` header

**auto-start at boot (systemd --user):**

```bash
<h1 align="center">copy service file</h1>

mkdir -p ~/.config/systemd/user
cp ~/holmes-project/jellyfin/holmes-jellyfin.service ~/.config/systemd/user/

<h1 align="center">edit to match your jellyfin url if needed, then enable</h1>

systemctl --user enable --now holmes-jellyfin-proxy
systemctl --user status holmes-jellyfin-proxy
```

**troubleshooting:**

```bash
<h1 align="center">check proxy health</h1>

curl http://localhost:5050/health

<h1 align="center">view proxy logs</h1>

journalctl --user -u holmes-jellyfin-proxy -f
```

---

<h2 align="center">4. nextcloud — holmesviewer app</h2>


<h3 align="center">install the app</h3>


```bash
<h1 align="center">1. copy to your nextcloud apps directory</h1>

<h1 align="center">(adjust the path to match your nextcloud install)</h1>

nextcloud_path="${home}/nextcloud"          # or /var/www/nextcloud
src="${home}/holmes-project/nextcloud/apps/holmesviewer"
sudo cp -r "$src" "${nextcloud_path}/apps/"

<h1 align="center">2. enable via occ</h1>

cd "$nextcloud_path"
sudo -u www-data php occ app:enable holmesviewer

<h1 align="center">3. restart php-fpm if needed</h1>

sudo systemctl restart php8.2-fpm   # adjust php version
```

<h3 align="center">how it works</h3>


- when nextcloud reads a `.holmes` file it discovers the inner mime type from
  the file inspector (since the file is already locally stored, it can read
  the header)
- the viewer route `get /apps/holmesviewer/view/{fileid}` strips the header
  and streams the inner payload with the correct `content-type`

<h3 align="center">play / preview a .holmes file in nextcloud</h3>


1. upload the .holmes file to nextcloud like any other file
2. click the file in the nextcloud file browser
3. nextcloud calls `get /apps/holmesviewer/view/{fileid}` which returns
   the inner media with the correct mime type — the nextcloud built-in
   media player / image preview picks it up automatically

<h3 align="center">verify the app is running</h3>


```
get /apps/holmesviewer/view/<some-holmes-fileid>
→ 200 ok with the inner media content-type header
```

<h3 align="center">troubleshooting</h3>


```bash
<h1 align="center">check app status</h1>

sudo -u www-data php occ app:list | grep holmesviewer

<h1 align="center">check php/nginx error logs for parse errors</h1>

journalctl --user -u nginx -e | grep holmesviewer
grep holmesviewer /var/log/nginx/error.log

<h1 align="center">check routes are registered</h1>

sudo -u www-data php occ route:list | grep holmesviewer
```

---

<h2 align="center">5. verify everything works</h2>


```bash
<h1 align="center">run core tests (format + tools)</h1>

cd ~/holmes-project
pythonpath=core/bin python3 core/tests/test_core.py

<h1 align="center">create a test .holmes and check it in editor</h1>

~/holmes-project/core/bin/holmes ~/pictures -o ~/holmes-project/test-media

<h1 align="center">open in editor — double-click a .holmes file in browser</h1>

~/editor/edit

<h1 align="center">verify jellyfin proxy is running</h1>

curl -s http://localhost:5050/health

<h1 align="center">check nextcloud app is enabled</h1>

[run nextcloud occ app:list and grep holmesviewer]
```

---

<h2 align="center">6. project layout</h2>


```
~/holmes-project/
├── core/
│   ├── bin/
│   │   ├── holmes              ← batch converter (main cli)
│   │   ├── holmes-extract      ← extract inner payload
│   │   ├── holmes-verify       ← validate .holmes files
│   │   ├── holmes-info         ← show human-readable info
│   │   └── holmes.py           ← python library (struct-based parser)
│   └── tests/
│       └── test_core.py        ← 9 end-to-end tests (format + tools)
├── editor-patch/               ← editor modification task briefs
├── jellyfin/
│   ├── holmes_jellyfin_proxy.py     ← flask reverse proxy
│   └── holmes-jellyfin.service      ← systemd --user unit
├── nextcloud/
│   └── apps/holmesviewer/      ← nextcloud app
│       ├── appinfo/
│       │   ├── info.xml
│       │   └── routes.php
│       ├── lib/
│       │   ├── app.php
│       │   ├── controller/
│       │   │   └── viewcontroller.php
│       │   └── utils/
│       │       └── holmesparser.php
├── docs/                       ← you are here
└── test-media/                 ← converted test files go here
```

---

<h2 align="center">quick reference</h2>


| task | command |
|------|---------|
| convert folder | `holmes ~/pictures` |
| extract one | `holmes-extract file.holmes file.jpg` |
| verify | `holmes-verify file.holmes` |
| info | `holmes-info file.holmes` |
| run tests | `pythonpath=core/bin python3 core/tests/test_core.py` |
| start jellyfin proxy | `python3 ~/holmes-project/jellyfin/holmes_jellyfin_proxy.py` |
| jellyfin proxy health | `curl http://localhost:5050/health` |
| enable nextcloud app | `occ app:enable holmesviewer` |
