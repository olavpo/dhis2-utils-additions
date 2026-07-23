import requests
import argparse
from requests.auth import HTTPBasicAuth
from urllib.parse import urlparse

def fetch_organisation_units(url, auth):
    api_url = f"{url}/api/organisationUnits.json"
    params = {
        "fields": "id,name,contactPerson,phoneNumber,address,email",
        "paging": "false",
        "filter": [
            "contactPerson:!null",
            "phoneNumber:!null",
            "address:!null",
            "email:!null"
        ],
        "rootJunction": "OR"
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

def clear_contact_info(url, org_units, auth):
    for org_unit in org_units:
        org_id = org_unit["id"]
        patch_url = f"{url}/api/organisationUnits/{org_id}"
        payload = [
            {"op": "remove", "path": "/contactPerson"},
            {"op": "remove", "path": "/phoneNumber"},
            {"op": "remove", "path": "/address"},
            {"op": "remove", "path": "/email"}
        ]

        try:
            response = requests.patch(
                patch_url,
                json=payload,
                auth=auth,
                headers={"Content-Type": "application/json-patch+json"}
            )
            response.raise_for_status()
            print(f"Successfully cleared contact info for {org_unit['name']} (ID: {org_id})")
        except requests.exceptions.HTTPError as e:
            print(f"Error: Failed to clear contact info for {org_unit['name']}. HTTP status: {response.status_code}. Full error: {e}")
        except requests.exceptions.RequestException as e:
            print(f"Error clearing contact info for {org_unit['name']}: {e}")

def main():
    parser = argparse.ArgumentParser(description="Clear contact info from DHIS2 organisation units.")
    parser.add_argument("--url", required=True, help="DHIS2 base URL (e.g., http://localhost:8888/sl)")
    parser.add_argument("--auth", required=True, help="Authentication in user:password format")
    args = parser.parse_args()

    # Validate URL format
    if not args.url.startswith(('http://', 'https://')):
        print("Error: URL must start with 'http://' or 'https://'")
        return

    user, password = args.auth.split(":")
    org_units = fetch_organisation_units(args.url, HTTPBasicAuth(user, password))

    if not org_units:
        print("No organisation units found with contact info, or an error occurred.")
        return

    print(f"Found {len(org_units)} organisation units with contact info. Clearing...")
    clear_contact_info(args.url, org_units, HTTPBasicAuth(user, password))

if __name__ == "__main__":
    main()
