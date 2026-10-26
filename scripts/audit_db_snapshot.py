# Safety snapshot of the live Library Manager database before audit/test work.
# Uses VACUUM INTO (validate-before-touch; never a raw file copy of a live DB),
# then runs integrity + schema checks on the snapshot itself.
# Author: release engineering (Phase 0 baseline)
import os
import sqlite3
import sys

src = os.path.join(os.environ["USERPROFILE"], "Documents", "library_manager.db")
dst = os.path.join(
    os.environ["USERPROFILE"],
    "Documents",
    "library_backups",
    "library_pre_audit_2026-10-19.db",
)

if not os.path.exists(src):
    print("NO live database found at", src)
    sys.exit(2)

print(f"source: {src} ({os.path.getsize(src)} bytes)")

# VACUUM INTO a brand-new file (fails safely if dst already exists)
if os.path.exists(dst):
    print("snapshot already exists, refusing to overwrite:", dst)
    sys.exit(3)
con = sqlite3.connect(src)
try:
    con.execute("VACUUM INTO ?", (dst,))
finally:
    con.close()

# Validate the snapshot before calling it a backup
v = sqlite3.connect(dst)
try:
    ok = v.execute("PRAGMA integrity_check").fetchone()[0]
    ver = v.execute("PRAGMA user_version").fetchone()[0]
    objs = v.execute(
        "SELECT COUNT(*) FROM sqlite_master WHERE type IN ('table','index')"
    ).fetchone()[0]
    counts = {}
    for t in ("items", "item_copies", "members", "loans", "reservations", "users"):
        try:
            counts[t] = v.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
        except sqlite3.Error:
            counts[t] = "n/a"
finally:
    v.close()

print(f"snapshot: {dst} ({os.path.getsize(dst)} bytes)")
print(f"integrity_check: {ok} | schema user_version: {ver} | tables+indexes: {objs}")
print("row counts:", counts)
if ok != "ok":
    sys.exit(1)
print("BACKUP VERIFIED OK")
