#!/bin/bash
#
# replace_uid.sh
#
# Replaces every occurrence of one string (typically a DHIS2 UID) with
# another in a file, in place. Handy when re-pointing an exported metadata
# or data file at a different object, e.g. swapping a category option combo
# or org unit UID before import.
#
# Usage:
#   ./replace_uid.sh <file> <old-uid> <new-uid>
#
# Example:
#   ./replace_uid.sh datavalues.json VYHuIGXpfow wnsR66pfYZ1
#
# Works on both Linux (GNU sed) and macOS (BSD sed).

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <file> <old-uid> <new-uid>"
  exit 1
fi

input_file="$1"
search_string="$2"
replace_string="$3"

if [ ! -f "$input_file" ]; then
  echo "Error: file not found: $input_file"
  exit 1
fi

# Portable in-place edit (BSD sed needs -i '', GNU sed doesn't accept it)
temp_file=$(mktemp)
sed -e "s/${search_string}/${replace_string}/g" "$input_file" > "$temp_file"
mv "$temp_file" "$input_file"

echo "Replaced '$search_string' with '$replace_string' in $input_file."
