"""Reads FLauncher's own app list and categories, from a copy pulled off the projector.

    python scripts/analysis/flauncher_db.py .scratch/flauncher-db/db.sqlite

FLauncher draws a tile only for an app placed in a category (`apps_categories`). An app
it finds later lands in `apps` alone and is never drawn -- the 2026-10-25 finding. A
reinstall is "later": uninstalling drops the app's rows, installing adds it back
uncategorised. Read-only: opens a copy, and never the projector's own file.
"""
import sqlite3
import sys

db = sqlite3.connect(sys.argv[1] if len(sys.argv) > 1 else ".scratch/flauncher-db/db.sqlite")
db.row_factory = sqlite3.Row
print("tables:", [r[0] for r in db.execute("select name from sqlite_master where type='table'")])
for t in ("apps", "categories", "apps_categories"):
    cols = [r[1] for r in db.execute(f"pragma table_info({t})")]
    print(f"\n== {t}: {cols}")
    for r in db.execute(f"select * from {t}"):
        print("  ", {k: r[k] for k in r.keys() if k not in ("banner", "icon")})
print("\n== in apps but in no category (never drawn):")
for r in db.execute(
        "select package_name, name, hidden from apps where package_name not in "
        "(select app_package_name from apps_categories)"):
    print("  ", dict(r))
