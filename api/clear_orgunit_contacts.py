"""Clear contact information from DHIS2 organisation units.

Finds all organisation units that have any of contactPerson, phoneNumber,
address or email set, and removes those fields. Useful when preparing a
database for use as a demo/training instance, where real contact details
should not be exposed.

Usage:
    python clear_orgunit_contacts.py --url https://localhost:8080 --auth admin:district
    python clear_orgunit_contacts.py --url ... --auth ... --dry-run

Requires: requests
"""

import argparse

import requests
from requests.auth import HTTPBasicAuth

CONTACT_FIELDS = ["contactPerson", "phoneNumber", "address", "email"]


def fetch_organisation_units(url, auth):
    api_url = f"{url}/api/organisationUnits.json"
    params = {
        "fields": "id,name," + ",".join(CONTACT_FIELDS),
        "paging": "false",
        "filter": [f"{field}:!null" for field in CONTACT_FIELDS],
        "rootJunction": "OR",
    }

    try:
        response = requests.get(api_url, params=params, auth=auth)
        response.raise_for_status()
        return response.json().get("organisationUnits", [])
    except requests.exceptions.MissingSchema as e:
        print(f"Error: Invalid URL. Please include 'http://' or 'https://' in the URL. Full error: {e}")
    except requests.exceptions.ConnectionError as e:
        print(f"Error: Could not connect to the server at {url}. Please check the URL and ensure the server is running. Full error: {e}")
    except requests.exceptions.HTTPError as e:
        print(f"Error: HTTP request failed with status {response.status_code}. Full error: {e}")
    except requests.exceptions.RequestException as e:
        print(f"Error fetching organisation units: {e}")
    return []


def clear_contact_info(url, org_units, auth, dry_run=False):
    for org_unit in org_units:
        org_id = org_unit["id"]
        # Only remove the fields this org unit actually has - a JSON patch
        # "remove" on a missing path fails.
        present_fields = [f for f in CONTACT_FIELDS if org_unit.get(f)]
        if not present_fields:
            continue

        if dry_run:
            print(f"[dry-run] Would clear {', '.join(present_fields)} for {org_unit['name']} (ID: {org_id})")
            continue

        patch_url = f"{url}/api/organisationUnits/{org_id}"
        payload = [{"op": "remove", "path": f"/{field}"} for field in present_fields]

        try:
            response = requests.patch(
                patch_url,
                json=payload,
                auth=auth,
                headers={"Content-Type": "application/json-patch+json"},
            )
            response.raise_for_status()
            print(f"Successfully cleared {', '.join(present_fields)} for {org_unit['name']} (ID: {org_id})")
        except requests.exceptions.HTTPError as e:
            print(f"Error: Failed to clear contact info for {org_unit['name']}. HTTP status: {response.status_code}. Full error: {e}")
        except requests.exceptions.RequestException as e:
            print(f"Error clearing contact info for {org_unit['name']}: {e}")


def main():
    parser = argparse.ArgumentParser(description="Clear contact info from DHIS2 organisation units.")
    parser.add_argument("--url", required=True, help="DHIS2 base URL (e.g., https://localhost:8080)")
    parser.add_argument("--auth", required=True, help="Authentication in user:password format")
    parser.add_argument("--dry-run", action="store_true", help="List what would be cleared without changing anything")
    args = parser.parse_args()

    if not args.url.startswith(("http://", "https://")):
        print("Error: URL must start with 'http://' or 'https://'")
        return

    url = args.url.rstrip("/")
    user, password = args.auth.split(":", 1)
    auth = HTTPBasicAuth(user, password)
    org_units = fetch_organisation_units(url, auth)

    if not org_units:
        print("No organisation units found with contact info, or an error occurred.")
        return

    print(f"Found {len(org_units)} organisation units with contact info.")
    clear_contact_info(url, org_units, auth, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
