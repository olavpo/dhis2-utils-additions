#!/bin/bash

# Define input file, search string, and replace string
input_file="$1"
search_string="VYHuIGXpfow"
replace_string="wnsR66pfYZ1"

# Use sed to perform the replacement
sed -i '' -e "s/${search_string}/${replace_string}/g" ${input_file}
