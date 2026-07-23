#!/bin/bash
#
# shift_json_years.sh
#
# Shifts all years one year forward in the "period", "created" and
# "lastUpdated" fields of a DHIS2 JSON export (data value sets, events,
# metadata). Useful for refreshing exported demo/training data so it appears
# one year more recent before re-import.
#
# Only the year component is changed (e.g. period "202301" becomes "202401");
# months, weeks and days are untouched.
#
# Usage:
#   ./shift_json_years.sh <file.json> [first-year] [last-year]
#
#   file.json    JSON file, modified IN PLACE (keep a copy if unsure)
#   first-year   oldest year to shift (default: 2013)
#   last-year    newest year to shift (default: 2025)
#
# Example: shift all years 2015-2024 forward by one in export.json
#   ./shift_json_years.sh export.json 2015 2024

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <file.json> [first-year] [last-year]"
  exit 1
fi

input_file="$1"
first_year="${2:-2013}"
last_year="${3:-2025}"

if [ ! -f "$input_file" ]; then
  echo "Error: file not found: $input_file"
  exit 1
fi

temp_file=$(mktemp)

# Work from the newest year down, so a year is never shifted twice
# (e.g. 2023->2024 must not later be caught by the 2024->2025 pass).
for year in $(seq "$last_year" -1 "$first_year"); do
  next_year=$((year + 1))
  echo "$year -> $next_year"
  # Only replace years directly following a "period"/"lastUpdated"/"created" key
  sed -E "s/(\"period\": ?\"|\"lastUpdated\": ?\"|\"created\": ?\")$year/\1$next_year/g" "$input_file" > "$temp_file"
  mv "$temp_file" "$input_file"
done

echo "Year replacements completed in $input_file."
