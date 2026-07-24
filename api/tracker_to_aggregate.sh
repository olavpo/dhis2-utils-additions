#!/bin/bash
#
# Transfers program indicator values into aggregate data elements, via
# the analytics API: program indicator values are exported as a data
# value set (with the target data element CODE taken from an attribute
# on each program indicator), then imported as aggregate data.
#
# This is the standard "tracker to aggregate" pattern: each program
# indicator carries a metadata attribute whose value is the CODE of the
# aggregate data element it feeds. See the DHIS2 tracker-to-aggregate
# integration guide for the full setup.
#
# Prerequisites:
#   * a TEXT metadata attribute assigned to program indicators, holding
#     the target data element code
#   * analytics tables generated on the source instance (the export
#     reads analytics, not raw data)
#   * if the program indicators also set aggregateExportCategoryOptionCombo/
#     aggregateExportAttributeOptionCombo, those must be COC codes
#
# Usage:
#   tracker_to_aggregate.sh -s <source-url> -u <user:pass> \
#       -p <pi-uid;pi-uid;...> -A <attribute-uid> -l <orgunit-level> \
#       [-e <periods>] [-t <target-url>] [-U <target-user:pass>] \
#       [-c <comment>] [-o <output-file>] [-n]
#
#   -s  Source base URL (no trailing slash), e.g. https://hmis.example.org
#   -u  Source credentials, user:password
#   -p  Program indicator UIDs, semicolon-separated
#   -A  UID of the attribute holding the target data element code
#   -l  Org unit level to export/import at
#   -e  Periods (relative or fixed, semicolon-separated). Default: LAST_12_MONTHS
#   -t  Target base URL. Default: same as source
#   -U  Target credentials. Default: same as source
#   -c  Comment stored on each imported value (default: tracker_aggregates_<date>).
#       Makes imported values identifiable: ... WHERE comment = '<comment>'
#   -o  File to save the exported data value set (default: tracker_aggregates_<date>.json)
#   -n  Dry run: fetch and save the export, validate the import, change nothing

set -euo pipefail

PERIODS="LAST_12_MONTHS"
DATE_ISO=$(date -u +"%Y-%m-%d")
COMMENT="tracker_aggregates_${DATE_ISO}"
OUTFILE=""
TARGET_URL=""
TARGET_AUTH=""
DRY_RUN="false"
SOURCE_URL=""; SOURCE_AUTH=""; PI_UIDS=""; ATTRIBUTE_UID=""; OU_LEVEL=""

while getopts "s:u:p:A:l:e:t:U:c:o:n" OPT; do
    case $OPT in
        s) SOURCE_URL="$OPTARG" ;;
        u) SOURCE_AUTH="$OPTARG" ;;
        p) PI_UIDS="$OPTARG" ;;
        A) ATTRIBUTE_UID="$OPTARG" ;;
        l) OU_LEVEL="$OPTARG" ;;
        e) PERIODS="$OPTARG" ;;
        t) TARGET_URL="$OPTARG" ;;
        U) TARGET_AUTH="$OPTARG" ;;
        c) COMMENT="$OPTARG" ;;
        o) OUTFILE="$OPTARG" ;;
        n) DRY_RUN="true" ;;
        *) exit 1 ;;
    esac
done

if [ -z "$SOURCE_URL" ] || [ -z "$SOURCE_AUTH" ] || [ -z "$PI_UIDS" ] || [ -z "$ATTRIBUTE_UID" ] || [ -z "$OU_LEVEL" ]; then
    echo "Missing required arguments; see header of this script." >&2
    exit 1
fi

TARGET_URL="${TARGET_URL:-$SOURCE_URL}"
TARGET_AUTH="${TARGET_AUTH:-$SOURCE_AUTH}"
OUTFILE="${OUTFILE:-tracker_aggregates_${DATE_ISO}.json}"

EXPORT_URL="${SOURCE_URL}/api/analytics/dataValueSet.json?dimension=dx:${PI_UIDS}&dimension=pe:${PERIODS}&dimension=ou:LEVEL-${OU_LEVEL}&outputIdScheme=ATTRIBUTE:${ATTRIBUTE_UID}"

echo "Exporting: ${EXPORT_URL}"
curl --fail-with-body -s -u "$SOURCE_AUTH" "$EXPORT_URL" \
    | sed "s/\[aggregated\]/${COMMENT}/g" > "$OUTFILE"
echo "Saved $(grep -o '"dataElement"' "$OUTFILE" | wc -l | tr -d ' ') data values to ${OUTFILE}"

IMPORT_URL="${TARGET_URL}/api/dataValueSets?dataElementIdScheme=CODE&categoryOptionComboIdScheme=CODE&importStrategy=CREATE_AND_UPDATE&dryRun=${DRY_RUN}"

echo "Importing: ${IMPORT_URL}"
curl --fail-with-body -s -X POST -u "$TARGET_AUTH" \
    -H "Content-Type: application/json" -d @"$OUTFILE" "$IMPORT_URL"
echo
if [ "$DRY_RUN" = "true" ]; then
    echo "Dry run - nothing imported. Export kept in ${OUTFILE}"
fi
