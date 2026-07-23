# API tools

Scripts that operate on a running DHIS2 instance through the Web API. Base
URL and credentials are passed as arguments — nothing is hardcoded.

## Tools

### `clear_orgunit_contacts.py`

Removes contact information (contactPerson, phoneNumber, address, email)
from all organisation units that have any of it. Typical use: preparing a
copy of a real database for use as a demo/training instance.

```bash
pip install requests

# see what would be removed
python clear_orgunit_contacts.py --url https://myserver/dhis --auth admin:district --dry-run

# remove it
python clear_orgunit_contacts.py --url https://myserver/dhis --auth admin:district
```

Only the fields actually present on each org unit are patched.

### `disable_category_dimensions.sh`

Bulk-disables (or enables) the *data dimension* flag on categories, so they
no longer clutter the dimension list in Data Visualizer and friends.

```bash
# disable
./disable_category_dimensions.sh https://myserver/dhis admin:district uid1,uid2,uid3

# re-enable
./disable_category_dimensions.sh https://myserver/dhis admin:district uid1,uid2,uid3 true
```

Run Analytics Tables export afterwards for the change to take effect in
analytics.

## Version compatibility

| Tool | 2.40 | 2.41 | 2.42 | 2.43 |
|---|---|---|---|---|
| `clear_orgunit_contacts.py` | ✅ | ✅ | ✅ | ✅ |
| `disable_category_dimensions.sh` | ✅ | ✅ | ✅ | ✅ |
