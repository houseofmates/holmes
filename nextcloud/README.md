# HolmeSviewer — Nextcloud App

Registers `.holmes` as a known MIME type in Nextcloud and provides a
route that extracts and streams the inner media payload.

## Structure

```
holmesviewer/
├── appinfo/
│   ├── info.xml          — Nextcloud app manifest (name, id, version)
│   └── routes.php        — route registrations
├── lib/
│   ├── App.php           — app bootstrap
│   ├── MimeRegistrar.php — registers application/x-holmes mime type
│   ├── Utils/
│   │   └── Holmes.php    — holmes binary parser + extractor
│   └── Controller/
│       └── ViewController.php — streaming route (GET /apps/holmesviewer/view/{fileId})
└── css/
    └── style.css         — optional custom view styles
```

## Install

```bash
# 1. copy to Nextcloud's apps directory
cp -r holmesviewer /home/nextcloud/apps/

# 2. enable
cd /home/nextcloud && sudo -u www-data php occ app:enable holmesviewer

# 3. restart php-fpm / apache / nginx if using php-fpm
sudo systemctl restart php8.2-fpm   # adjust version to your install
```

The app has no external PHP dependencies — it uses only Nextcloud core APIs.

## Notes

- the app registers `application/x-holmes` as Nextcloud's internal MIME for `.holmes` extension, so Nextcloud will not try to display it as plain text.
- the preview / view route works only when the user has `read` permission on the file (Nextcloud's share system enforces this).
- Jellyfin is a separate system — this app is solely for Nextcloud.
