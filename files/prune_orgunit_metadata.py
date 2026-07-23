"""Prune a DHIS2 org unit metadata export down to its essential fields.

Reads a metadata.json containing organisationUnits, organisationUnitGroups,
organisationUnitGroupSets and organisationUnitLevels, and strips each object
down to the fields needed to recreate the org unit hierarchy elsewhere
(names, IDs, relationships, geometry, opening dates). Everything else -
sharing, access, attribute values, audit fields etc. - is dropped, which
typically shrinks the file dramatically and avoids importing irrelevant
detail into the target instance.

Usage:
    python prune_orgunit_metadata.py metadata.json [-o metadata_pruned.json]

Sections that are missing from the input are skipped.
"""

import argparse
import json


def prune(data):
    if "organisationUnitGroups" in data:
        data["organisationUnitGroups"] = [
            {
                "name": group["name"],
                "shortName": group["shortName"],
                "id": group["id"],
                "organisationUnits": group["organisationUnits"],
            }
            for group in data["organisationUnitGroups"]
        ]

    if "organisationUnitGroupSets" in data:
        data["organisationUnitGroupSets"] = [
            {
                "name": group_set["name"],
                "shortName": group_set["shortName"],
                "id": group_set["id"],
                "organisationUnitGroups": group_set["organisationUnitGroups"],
                "dataDimension": group_set.get("dataDimension", None),
                "compulsory": group_set.get("compulsory", None),
            }
            for group_set in data["organisationUnitGroupSets"]
        ]

    if "organisationUnitLevels" in data:
        data["organisationUnitLevels"] = [
            {
                "name": level["name"],
                "id": level["id"],
                "level": level["level"],
            }
            for level in data["organisationUnitLevels"]
        ]

    if "organisationUnits" in data:
        data["organisationUnits"] = [
            {
                "name": unit["name"],
                "shortName": unit.get("shortName", None),
                "id": unit["id"],
                "level": unit.get("level", None),
                "parent": unit.get("parent", None),
                "path": unit.get("path", None),
                "geometry": unit.get("geometry", None),
                "openingDate": unit.get("openingDate", None),
            }
            for unit in data["organisationUnits"]
        ]

    return data


def main():
    parser = argparse.ArgumentParser(description="Prune a DHIS2 org unit metadata export to essential fields.")
    parser.add_argument("input", help="Input metadata JSON file")
    parser.add_argument("-o", "--output", default="metadata_pruned.json", help="Output file (default: metadata_pruned.json)")
    args = parser.parse_args()

    with open(args.input, "r") as file:
        data = json.load(file)

    data = prune(data)

    with open(args.output, "w") as file:
        json.dump(data, file, indent=4)

    print(f"Pruned metadata saved to '{args.output}'")


if __name__ == "__main__":
    main()
