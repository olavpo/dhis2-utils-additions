#!/bin/sh
#
# Strips verbose formatting from custom data entry form HTML, e.g. forms
# pasted from MS Word: presentational tags (span/font/b/strong/small/p),
# inline styles and layout attributes, leaving the table structure and
# input fields. Input fields get a uniform centered style.
#
# Review the result before uploading — the cleanup is aggressive and
# removes ALL inline styling.
#
# Usage: ./clean_custom_form_html.sh <form.html>
#
# The file is modified in place (works with both GNU and BSD sed).

set -eu

if [ $# -lt 1 ]; then
    echo "Usage: $0 <form.html>"
    exit 1
fi

FILE="$1"
TMP="$(mktemp)"

sed \
    -e 's/<tr[^>]*>/<tr>/g' \
    -e 's/<p[^>]*>//g' \
    -e 's/<\/p>//g' \
    -e 's/<b[^>]*>//g' \
    -e 's/<\/b>//g' \
    -e 's/<span[^>]*>//g' \
    -e 's/<\/span>//g' \
    -e 's/<strong[^>]*>//g' \
    -e 's/<\/strong>//g' \
    -e 's/<small[^>]*>//g' \
    -e 's/<\/small>//g' \
    -e 's/<font[^>]*>//g' \
    -e 's/<\/font>//g' \
    -e 's/style="[^"]*"//g' \
    -e 's/width="[^"]*"//g' \
    -e 's/nowrap="[^"]*"//g' \
    -e 's/valign="[^"]*"//g' \
    -e 's/view="[^"]*"//g' \
    -e 's/bgcolor="[^"]*"//g' \
    -e 's/&nbsp;/ /g' \
    -e 's/<input/<input style="width:7em;text-align:center;"/g' \
    "$FILE" > "$TMP"

mv "$TMP" "$FILE"
echo "Cleaned $FILE"
