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
      [--group Family] [--public-group "Friends & Family"]

--public-group sets up an EXTERNAL group with a shareable public link
(anyone with the URL can join — no email invites, no ASC accounts),
assigns the newest processed build to it, and submits that build for
Beta App Review, which is what activates the link (typically <24 h).
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
    ap.add_argument("--public-group", default="")
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

    # Re-send the invitation email (a stale link shows "revoked or
    # invalid"; a fresh invitation replaces it).
    status, out = api(
        "GET", f"/v1/betaTesters?filter[email]={urllib.request.quote(args.tester)}")
    testers = out.get("data", []) if status == 200 else []
    if testers:
        status, out = api("POST", "/v1/betaTesterInvitations", {
            "data": {"type": "betaTesterInvitations",
                     "relationships": {
                         "betaTester": {"data": {"type": "betaTesters",
                                                 "id": testers[0]["id"]}},
                         "app": {"data": {"type": "apps", "id": app_id}}}}})
        if status == 201:
            print(f"re-sent TestFlight invitation to {args.tester}")
        else:
            print(f"::warning::could not re-send invitation ({status}): {out}")

    # Latest builds and their Apple-side processing state.
    status, out = api(
        "GET", f"/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=5")
    builds = out.get("data", []) if status == 200 else []
    if builds:
        print("recent builds:")
        for b in builds:
            at = b["attributes"]
            print(f"  build {at.get('version')}: {at.get('processingState')}"
                  f" (uploaded {at.get('uploadedDate')})")
    else:
        print("no builds have reached App Store Connect yet")

    if args.public_group:
        setup_public_link(app_id, args.public_group, builds,
                          feedback_email=args.tester or "")


def setup_public_link(app_id, group_name, builds, feedback_email):
    """External group + shareable public link + Beta App Review submission
    for the newest processed build (review approval activates the link)."""
    # Beta App Review requires test information to exist.
    status, out = api(f"GET", f"/v1/apps/{app_id}/betaAppLocalizations")
    locs = out.get("data", []) if status == 200 else []
    if not any(l["attributes"].get("locale") == "en-US" for l in locs):
        status, out = api("POST", "/v1/betaAppLocalizations", {
            "data": {"type": "betaAppLocalizations",
                     "attributes": {
                         "locale": "en-US",
                         "description": ("BabyBand Jam is a music toy for "
                                         "toddlers: drums, guitar, xylophone, "
                                         "trombone, piano, and bongos. Every "
                                         "sound is synthesized and leveled for "
                                         "built-in speakers."),
                         "feedbackEmail": feedback_email or "noreply@example.com"},
                     "relationships": {"app": {"data": {
                         "type": "apps", "id": app_id}}}}})
        if status == 201:
            print("created TestFlight test information (en-US)")
        else:
            print(f"::warning::could not create beta app info ({status}): {out}")

    # External group with a public link.
    quoted = urllib.request.quote(group_name)
    status, out = api(
        "GET", f"/v1/betaGroups?filter[app]={app_id}&filter[name]={quoted}")
    groups = out.get("data", []) if status == 200 else []
    if groups:
        group = groups[0]
    else:
        status, out = api("POST", "/v1/betaGroups", {
            "data": {"type": "betaGroups",
                     "attributes": {"name": group_name,
                                    "isInternalGroup": False,
                                    "publicLinkEnabled": True,
                                    "publicLinkLimitEnabled": False},
                     "relationships": {"app": {"data": {
                         "type": "apps", "id": app_id}}}}})
        if status != 201:
            fail(f"could not create external group ({status}): {out}")
        group = out["data"]
        print(f"created external group \"{group_name}\"")
    group_id = group["id"]
    if not group["attributes"].get("publicLinkEnabled"):
        status, out = api("PATCH", f"/v1/betaGroups/{group_id}", {
            "data": {"type": "betaGroups", "id": group_id,
                     "attributes": {"publicLinkEnabled": True,
                                    "publicLinkLimitEnabled": False}}})
        if status == 200:
            group = out["data"]

    # Beta App Review requires a review contact. The phone number comes
    # from a repo secret (this is a public repo — workflow inputs and
    # logs are world-readable, secrets are not).
    phone = os.environ.get("REVIEW_CONTACT_PHONE", "")
    if phone:
        status, out = api(f"GET", f"/v1/apps/{app_id}/betaAppReviewDetail")
        detail_id = out.get("data", {}).get("id") if status == 200 else None
        if detail_id:
            status, out = api("PATCH", f"/v1/betaAppReviewDetails/{detail_id}", {
                "data": {"type": "betaAppReviewDetails", "id": detail_id,
                         "attributes": {
                             "contactFirstName": os.environ.get("REVIEW_CONTACT_FIRST", "Andrew"),
                             "contactLastName": os.environ.get("REVIEW_CONTACT_LAST", "Callahan"),
                             "contactPhone": phone,
                             "contactEmail": feedback_email or "noreply@example.com"}}})
            if status == 200:
                print("beta review contact info set")
            else:
                print(f"::warning::could not set review contact ({status}): {out}")
    else:
        print("::warning::REVIEW_CONTACT_PHONE secret not set — beta review "
              "submission will fail until the review contact exists")

    # Newest fully processed build -> group + Beta App Review.
    valid = next((b for b in builds
                  if b["attributes"].get("processingState") == "VALID"), None)
    if not valid:
        print("::warning::no processed build to submit for beta review yet")
    else:
        # Export compliance must be answered on the build for external
        # testing; the app uses no non-exempt encryption.
        if valid["attributes"].get("usesNonExemptEncryption") is None:
            status, out = api("PATCH", f"/v1/builds/{valid['id']}", {
                "data": {"type": "builds", "id": valid["id"],
                         "attributes": {"usesNonExemptEncryption": False}}})
            if status == 200:
                print("export compliance set on build (no non-exempt encryption)")
            else:
                print(f"::warning::could not set export compliance ({status}): {out}")
        version = valid["attributes"].get("version")
        status, out = api("POST", f"/v1/betaGroups/{group_id}/relationships/builds",
                          {"data": [{"type": "builds", "id": valid["id"]}]})
        if status in (200, 204):
            print(f"assigned build {version} to \"{group_name}\"")
        else:
            print(f"::warning::could not assign build ({status}): {out}")
        status, out = api("POST", "/v1/betaAppReviewSubmissions", {
            "data": {"type": "betaAppReviewSubmissions",
                     "relationships": {"build": {"data": {
                         "type": "builds", "id": valid["id"]}}}}})
        if status == 201:
            print(f"submitted build {version} for Beta App Review "
                  "(the public link activates when it's approved, usually <24h)")
        elif status == 409:
            print(f"build {version} is already submitted/approved for beta review")
        else:
            print(f"::warning::beta review submission failed ({status}): {out}")

    status, out = api("GET", f"/v1/betaGroups/{group_id}")
    link = out.get("data", {}).get("attributes", {}).get("publicLink") if status == 200 else None
    if link:
        print(f"PUBLIC LINK: {link}")
    else:
        print("::warning::public link not available yet — re-run after review approval")


if __name__ == "__main__":
    main()
