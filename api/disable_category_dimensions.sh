#!/bin/bash
#
# disable_category_dimensions.sh
#
# Bulk-disables (or enables) the "data dimension" flag on categories, so they
# no longer appear as analysis dimensions in the analytics apps. Useful when
# an instance has many categories cluttering Data Visualizer et al.
#
# Usage:
#   ./disable_category_dimensions.sh <base-url> <user:password> <uid1,uid2,...> [true|false]
#
#   base-url        e.g. https://play.dhis2.org/40 (no trailing slash needed)
#   user:password   credentials of a user with metadata write access
#   uids            comma-separated category UIDs
#   true|false      optional value for dataDimension (default: false)
#
# Example:
#   ./disable_category_dimensions.sh https://localhost:8080 admin:district fbfJHSPpUQD,cX5k9anHEHd
#
# Run "Analytics Tables" export afterwards for the change to take effect in
# analytics.

set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <base-url> <user:password> <uid1,uid2,...> [true|false]"
  exit 1
fi

BASE_URL="${1%/}"
AUTH="$2"
IDS="$3"
VALUE="${4:-false}"

if [ "$VALUE" != "true" ] && [ "$VALUE" != "false" ]; then
  echo "Error: fourth argument must be 'true' or 'false' (got: $VALUE)"
  exit 1
fi

IFS=',' read -r -a id_array <<< "$IDS"

for ID in "${id_array[@]}"; do
  echo "Processing category: $ID"

  curl --fail-with-body -s "$BASE_URL/api/categories/$ID" \
    -u "$AUTH" \
    -X PATCH \
    -H 'Content-Type: application/json-patch+json' \
    --data-raw "[{\"op\":\"add\",\"path\":\"/dataDimension\",\"value\":$VALUE}]"
  echo

  # Small pause between requests to be gentle with the server
  sleep 1
done

echo "Done: set dataDimension=$VALUE on ${#id_array[@]} categories."
