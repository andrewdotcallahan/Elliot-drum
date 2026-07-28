#!/usr/bin/env python3
"""One-time App Store Connect setup/verification, run from GitHub Actions
(the "ASC setup" workflow) so the API key never leaves the repo secrets.

Does everything the public ASC API allows:
  * registers the bundle ID (idempotent — "already exists" is success)
  * reports the Team ID (the bundle ID's seedId) and cross-checks the
    APPLE_TEAM_ID secret
  * checks whether the App Store Connect app record exists (creating it
    is NOT possible via the public API — that step stays manual)
  * optionally ensures a TestFlight internal group exists and invites a
    tester email to it

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_API_KEY_P8 (key file contents),
     APPLE_TEAM_ID (optional, verified only)
Args: --bundle-id com.andrewhq.babyband [--tester you@example.com]
      [--group Family]
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt  # pyjwt + cryptography

BASE = "https://api.appstoreconnect.apple.com"


def token():
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900,
         "aud": "appstoreconnect-v1"},
        os.environ["ASC_API_KEY_P8"],
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"]},
    )


def api(method, path, body=None):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={"Authorization": f"Bearer {token()}",
                 "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def fail(msg):
    print(f"::error::{msg}")
    sys.exit(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bundle-id", required=True)
    ap.add_argument("--tester", default="")
    ap.add_argument("--group", default="Family")
    args = ap.parse_args()

    # -- Bundle ID ---------------------------------------------------------
    status, out = api("POST", "/v1/bundleIds", {
        "data": {"type": "bundleIds", "attributes": {
            "name": "BabyBand", "identifier": args.bundle_id,
            "platform": "IOS"}}})
    if status == 201:
        print(f"registered bundle ID {args.bundle_id}")
    elif status == 409:
        print(f"bundle ID {args.bundle_id} already registered — OK")
    else:
        fail(f"bundle ID registration failed ({status}): {out}")

    status, out = api(
        "GET", f"/v1/bundleIds?filter[identifier]={args.bundle_id}")
    entries = [d for d in out.get("data", [])
               if d["attributes"]["identifier"] == args.bundle_id]
    if status != 200 or not entries:
        fail(f"could not read back bundle ID ({status}): {out}")
    seed = entries[0]["attributes"].get("seedId", "")
    print(f"Team ID (seedId): {seed}")
    want = os.environ.get("APPLE_TEAM_ID", "")
    if want and seed and want != seed:
        print(f"::warning::APPLE_TEAM_ID secret is '{want}' but the bundle "
              f"ID's team is '{seed}' — double-check the secret.")
    elif want:
        print("APPLE_TEAM_ID secret matches — OK")

    # -- App record (read-only; API cannot create it) ----------------------
    status, out = api(
        "GET", f"/v1/apps?filter[bundleId]={args.bundle_id}")
    apps = out.get("data", []) if status == 200 else []
    if not apps:
        print("::warning::No App Store Connect app record for "
              f"{args.bundle_id} yet. Create it manually in ASC (New App) — "
              "the public API cannot do this step. TestFlight uploads will "
              "fail until it exists.")
        status, out = api("GET", "/v1/apps?limit=20")
        listing = out.get("data", []) if status == 200 else []
        if listing:
            print("apps that DO exist on this team:")
            for a in listing:
                at = a["attributes"]
                print(f"  \"{at.get('name')}\"  bundleId={at.get('bundleId')}")
        else:
            print("no app records exist on this team at all")
        if args.tester:
            print("skipping tester setup until the app record exists")
        return
    app_id = apps[0]["id"]
    print(f"app record exists: \"{apps[0]['attributes']['name']}\" ({app_id})")

    # -- Internal TestFlight group + tester --------------------------------
    if not args.tester:
        return
    status, out = api(
        "GET", f"/v1/betaGroups?filter[app]={app_id}"
               f"&filter[name]={urllib.request.quote(args.group)}")
    groups = out.get("data", []) if status == 200 else []
    if groups:
        group_id = groups[0]["id"]
        print(f"beta group \"{args.group}\" exists")
    else:
        status, out = api("POST", "/v1/betaGroups", {
            "data": {"type": "betaGroups",
                     "attributes": {"name": args.group,
                                    "isInternalGroup": True,
                                    "hasAccessToAllBuilds": True},
                     "relationships": {"app": {"data": {
                         "type": "apps", "id": app_id}}}}})
        if status != 201:
            fail(f"could not create beta group ({status}): {out}")
        group_id = out["data"]["id"]
        print(f"created internal beta group \"{args.group}\"")

    status, out = api("POST", "/v1/betaTesters", {
        "data": {"type": "betaTesters",
                 "attributes": {"email": args.tester},
                 "relationships": {"betaGroups": {"data": [
                     {"type": "betaGroups", "id": group_id}]}}}})
    if status == 201:
        print(f"invited {args.tester} to \"{args.group}\"")
    elif status == 409:
        print(f"{args.tester} is already a tester — OK")
    else:
        fail(f"could not add tester ({status}): {out}")


if __name__ == "__main__":
    main()
