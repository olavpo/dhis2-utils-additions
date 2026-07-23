import json

# Read the JSON file
with open('metadata.json', 'r') as file:
    data = json.load(file)

# Extract and clean organisationUnitGroups
cleaned_organisation_unit_groups = [
    {
        "name": group["name"],
        "shortName": group["shortName"],
        "id": group["id"],
        "organisationUnits": group["organisationUnits"]
    }
    for group in data["organisationUnitGroups"]
]

# Extract and clean organisationUnitGroupSets
cleaned_organisation_unit_group_sets = [
    {
        "name": group_set["name"],
        "shortName": group_set["shortName"],
        "id": group_set["id"],
        "organisationUnitGroups": group_set["organisationUnitGroups"],
        "dataDimension": group_set.get("dataDimension", None),
        "compulsory": group_set.get("compulsory", None)
    }
    for group_set in data["organisationUnitGroupSets"]
]

# Extract and clean organisationUnitLevels
cleaned_organisation_unit_levels = [
    {
        "name": level["name"],
        "id": level["id"],
        "level": level["level"]
    }
    for level in data["organisationUnitLevels"]
]

# Extract and clean organisationUnits
cleaned_organisation_units = [
    {
        "name": unit["name"],
        "shortName": unit.get("shortName", None),
        "id": unit["id"],
        "level": unit.get("level", None),
        "parent": unit.get("parent", None),
        "path": unit.get("path", None),
        "geometry": unit.get("geometry", None),
        "openingDate": unit.get("openingDate", None)
    }
    for unit in data["organisationUnits"]
]

# Update the original data structure
data["organisationUnitGroups"] = cleaned_organisation_unit_groups
data["organisationUnitGroupSets"] = cleaned_organisation_unit_group_sets
data["organisationUnitLevels"] = cleaned_organisation_unit_levels
data["organisationUnits"] = cleaned_organisation_units

# Save the cleaned data back to a JSON file
with open('metadata_pruned.json', 'w') as file:
    json.dump(data, file, indent=4)

print("Cleaned data has been saved to 'cleaned_file.json'")
