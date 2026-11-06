#!/usr/bin/env python3
"""
Prepares the data and settings the app downloads, signed, in DataPipeline/publish/out/ to upload to the host.

    DataPipeline/.venv/bin/python DataPipeline/publish.py keygen
    DataPipeline/.venv/bin/python DataPipeline/publish.py data [--min-app-build N]
    DataPipeline/.venv/bin/python DataPipeline/publish.py config path/to/config.json

Private keys stay in ~/.konstanzgo (never in git; back them up). `keygen` prints the public keys for
`DataHost.trustedKeys`. KONSTANZGO_KEY_DIR and KONSTANZGO_PUBLISH_DIR point elsewhere, for tests.
"""
import base64
import gzip
import hashlib
import json
import os
import sqlite3
import sys
import time
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "App/Resources/Data"
OUT = Path(os.environ.get("KONSTANZGO_PUBLISH_DIR", ROOT / "DataPipeline/publish/out"))
KEYS = Path(os.environ.get("KONSTANZGO_KEY_DIR", Path.home() / ".konstanzgo"))
# The files that can change without an app release; the map stays in the app.
FILES = ["timetable.db", "search/places.tsvz", "walk/konstanz-walk.bin"]


def public_key(private):
    raw = private.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    return base64.b64encode(raw).decode()


def load_key(name="data-signing-primary.pem"):
    return serialization.load_pem_private_key((KEYS / name).read_bytes(), password=None)


def keygen():
    KEYS.mkdir(parents=True, exist_ok=True, mode=0o700)
    for name in ["data-signing-primary.pem", "data-signing-spare.pem"]:
        path = KEYS / name
        if path.exists():
            print(f"{name}: kept, already exists")
            key = load_key(name)
        else:
            key = Ed25519PrivateKey.generate()
            path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                               serialization.NoEncryption()))
            path.chmod(0o600)
            print(f"{name}: created")
        print(f"  public: {public_key(key)}")
    print(f"Back up {KEYS} outside this computer. Losing both keys means an app release to replace them.")


def signed(name, data):
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / f"{name}.json").write_bytes(data)
    (OUT / f"{name}.sig").write_bytes(load_key().sign(data))


def publish_data(min_app_build):
    db = sqlite3.connect(DATA / "timetable.db")
    meta = dict(db.execute("SELECT key, value FROM meta"))
    schema = db.execute("PRAGMA user_version").fetchone()[0]
    version = int(time.time())
    files = []
    for path in FILES:
        raw = (DATA / path).read_bytes()
        name = f"{version}/{path}.gz"
        target = OUT / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(gzip.compress(raw, mtime=0))
        files.append({"path": path, "url": name, "sha256": hashlib.sha256(raw).hexdigest()})
    manifest = {"version": version, "feedVersion": meta["feed_version"], "schema": schema,
                "minAppBuild": min_app_build, "files": files}
    signed("manifest", json.dumps(manifest, indent=1).encode())
    print(f"data set {version}, feed {meta['feed_version']}, in {OUT}. Upload the numbered folder first, the manifest last.")


def publish_config(path):
    data = Path(path).read_bytes()
    json.loads(data)
    signed("config", data)
    print(f"config in {OUT}")


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "keygen":
        keygen()
    elif command == "data":
        publish_data(int(sys.argv[sys.argv.index("--min-app-build") + 1]) if "--min-app-build" in sys.argv else 0)
    elif command == "config":
        publish_config(sys.argv[2])
    else:
        sys.exit(__doc__)
