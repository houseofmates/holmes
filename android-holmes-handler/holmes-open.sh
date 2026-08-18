#!/bin/bash
# holmes-open — open a .holmes file on your Android phone via ADB
# run from the machine connected to the phone (.250 = desktop)
#
# usage: holmes-open <file.holmes>
#        holmes-open /path/to/something.holmes

set -e

PHONE_FILE="$1"

if [ -z "$PHONE_FILE" ]; then
    echo "usage: holmes-open <file.holmes>"
    echo "  file must already be on the phone"
    exit 1
fi

# Find the content:// URI from MediaStore
CONTENT_ID=$(adb shell "content query --uri content://media/external/file --projection _id:_data 2>/dev/null" \
    | grep -F "$PHONE_FILE" \
    | head -1 \
    | grep -oP '_id=\K[0-9]+')

if [ -n "$CONTENT_ID" ]; then
    URI="content://media/external/file/$CONTENT_ID"
else
    # fallback: file:// URI (needs MANAGE_EXTERNAL_STORAGE granted)
    URI="file:///storage/emulated/0${PHONE_FILE#/storage/emulated/0}"
    URI="file://$PHONE_FILE"
fi

echo "Opening: $URI"
adb shell am start -n com.houseofmates.holmeshandler/.HolmesOpenActivity -d "$URI" -t '*/*'
echo "Done."