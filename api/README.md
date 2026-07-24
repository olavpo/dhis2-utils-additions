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

### `tracker_to_aggregate.sh`

Transfers program indicator values into aggregate data elements via the
analytics API — the standard "tracker to aggregate" pattern. Each
program indicator carries a metadata attribute holding the CODE of the
target aggregate data element; the script exports the indicators as a
data value set with that attribute as ID scheme and imports it as
aggregate data (optionally into a different instance). Supports dry-run
(`-n`), and tags imported values with a comment so they can be
identified later.

```bash
./tracker_to_aggregate.sh -s https://hmis.example.org -u user:pass \
    -p 'jSEquR6y8Fx;Z7r9H312QOu' -A vudyDP7jUy5 -l 4 -e LAST_4_QUARTERS
```

Prerequisites: analytics tables generated on the source; a TEXT
attribute (assigned to program indicators) holding target data element
codes. Generalized from Olav's TB tracker-to-aggregate script.

**2.43+ is stricter on import**: the target data elements must belong
to a data set of the matching period type, and that data set must be
assigned to the org units being imported to — otherwise every value is
rejected with "Data set detection failed" / "not usable with org
unit(s)". On 2.40–2.42 the same import went through without a data
set. Real configurations normally satisfy this already.

## Version compatibility

| Tool | 2.40 | 2.41 | 2.42 | 2.43 |
|---|---|---|---|---|
| `clear_orgunit_contacts.py` | ✅ | ✅ | ✅ | ✅ |
| `disable_category_dimensions.sh` | ✅ | ✅ | ✅ | ✅ |
| `tracker_to_aggregate.sh` | ✅ | ✅ | ✅ | ✅ |
