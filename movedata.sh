#!/bin/bash

# Check if an input file is provided
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 filename"
  exit 1
fi

# Assign input file to a variable
input_file="$1"

# Create a temporary file to store intermediate results
temp_file=$(mktemp)

# Iterate over the years from 2025 down to 2013
years=$(seq 2025 -1 2013)

# Process each year
for year in $years; do
  next_year=$((year + 1))
  echo "$year to $next_year"
  # Replace years preceded by "period":" or "lastUpdated":"
  sed -E "s/(\"period\": ?\"|\"lastUpdated\": ?\"|\"created\": ?\")$year/\1$next_year/g" "$input_file" > "$temp_file"
  mv "$temp_file" "$input_file"
done

# Clean up
rm -f "$temp_file"

echo "Year replacements completed in $input_file."
