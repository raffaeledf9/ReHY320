"""Places an app back into a FLauncher category, in a copy of its database.

    python scripts/analysis/flauncher_place.py <db.sqlite> <package> <category_id> <order>

What FLauncher's own settings screen writes when an app is moved into a row: one row in
`apps_categories`. Needed after a reinstall, because uninstalling drops the app's place
and the reinstalled app comes back uncategorised, so it is never drawn. Works on a copy;
the copy is checkpointed into a single file so it can be put back without a stale WAL.
"""
import sqlite3
import sys

path, pkg, cat, order = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
db = sqlite3.connect(path)
if not db.execute("select 1 from apps where package_name=?", (pkg,)).fetchone():
    sys.exit(f"{pkg} is not in FLauncher's apps table")
if db.execute("select 1 from apps_categories where app_package_name=?", (pkg,)).fetchone():
    sys.exit(f"{pkg} already has a category; nothing to do")
taken = db.execute("select app_package_name from apps_categories where category_id=? and \"order\"=?",
                   (cat, order)).fetchone()
if taken:
    sys.exit(f"order {order} in category {cat} is taken by {taken[0]}")
db.execute("insert into apps_categories (category_id, app_package_name, \"order\") values (?,?,?)",
           (cat, pkg, order))
db.commit()
db.execute("pragma wal_checkpoint(TRUNCATE)")
db.execute("pragma journal_mode=DELETE")
print(db.execute("pragma integrity_check").fetchone()[0])
for r in db.execute("select category_id, \"order\", app_package_name from apps_categories "
                    "order by category_id, \"order\""):
    print("  ", r)
db.close()
