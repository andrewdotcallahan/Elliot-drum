#!/usr/bin/env python3
"""Prepare and submit the App Store release, run from GitHub Actions (the
"App Store publish" workflow) so the API key stays in repo secrets.

Does everything Apple's public API allows for a first release:
  * fills in version metadata (description, keywords, promo text, URLs)
  * sets app subtitle, privacy policy URL, and primary category
  * answers the age rating questionnaire (everything NONE -> 4+)
  * uploads the App Store screenshots committed under app-store/
  * sets the price schedule to Free (best effort)
  * attaches the requested build to the 1.0 version
  * creates/updates the App Review contact details
  * creates the review submission and submits it

Known UI-only gap: the App Privacy questionnaire ("Data Not Collected")
cannot be set via the public API; the final submit is blocked until the
account holder completes it once in App Store Connect.

Env: same as asc_setup.py plus REVIEW_CONTACT_PHONE.
"""

import argparse
import hashlib
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc_setup import api, fail  # noqa: E402

SUBTITLE = "Toddler drums, piano & more"
PROMO = ("Six real-sounding instruments for little hands — no ads, "
         "no purchases, no internet needed.")
KEYWORDS = ("toddler,baby,kids,music,drums,piano,xylophone,guitar,"
            "bongos,trombone,instruments,sounds")
DESCRIPTION = """\
BabyBand Jam is a music toy built for toddlers — six instruments that \
sound great, respond instantly, and can't be broken by enthusiastic \
little hands.

THE BAND
• Drums — a full 7-piece kit with cymbals that wobble when you crash them
• Guitar — strum anywhere and it's always a beautiful chord
• Xylophone — 8 rainbow bars, with follow-the-glow songs (Twinkle \
Twinkle and Mary Had a Little Lamb)
• Trombone — drag the slide for real glissando, just like the real thing
• Piano — big colorful keys made for small fingers
• Bongos — three hand drums sized for baby palms

BUILT FOR TODDLERS
• Every touch makes a sound — no menus, no wrong answers
• Full multitouch: chords, drum rolls, and two-handed mayhem all work
• Instrument switching is behind a press-and-hold parent button
• Works great with iOS Guided Access for full toddler-proofing
• All sounds are carefully leveled so nothing is harsh or too loud

FOR PARENTS
• No ads. No in-app purchases. No accounts.
• No data collection of any kind — the app is completely offline
• Nothing to unlock, nothing to subscribe to: the whole app, forever

Made by a dad for his one-and-a-half-year-old. Enjoy the racket!
"""
REVIEW_NOTES = ("App for toddlers; no account or setup needed. All sounds "
                "are synthesized originals. Instrument switching is behind "
                "a press-and-hold button (hold the note button in the top "
                "right ~1.5s).")

SCREENSHOT_SETS = [
    ("APP_IPHONE_65", "app-store/screenshots/iphone-65"),
    ("APP_IPAD_PRO_3GEN_129", "app-store/screenshots/ipad-129"),
]


def find_app(bundle_id):
    status, out = api("GET", f"/v1/apps?filter[bundleId]={bundle_id}")
    apps = out.get("data", []) if status == 200 else []
    if not apps:
        fail(f"no app record for {bundle_id}")
    return apps[0]["id"]


def ensure_version(app_id, version_string):
    status, out = api("GET", f"/v1/apps/{app_id}/appStoreVersions"
                             f"?filter[versionString]={version_string}")
    versions = out.get("data", []) if status == 200 else []
    if versions:
        v = versions[0]
        print(f"version {version_string} exists "
              f"({v['attributes'].get('appStoreState')})")
        return v["id"]
    status, out = api("POST", "/v1/appStoreVersions", {
        "data": {"type": "appStoreVersions",
                 "attributes": {"platform": "IOS",
                                "versionString": version_string,
                                "releaseType": "AFTER_APPROVAL"},
                 "relationships": {"app": {"data": {
                     "type": "apps", "id": app_id}}}}})
    if status != 201:
        fail(f"could not create version ({status}): {out}")
    print(f"created App Store version {version_string}")
    return out["data"]["id"]


def set_app_info(app_id, privacy_url):
    status, out = api("GET", f"/v1/apps/{app_id}/appInfos")
    infos = out.get("data", []) if status == 200 else []
    editable = next((i for i in infos if i["attributes"].get("appStoreState")
                     in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED",
                         "REJECTED", "METADATA_REJECTED")), None) \
        or (infos[0] if infos else None)
    if not editable:
        print("::warning::no editable app info found")
        return None
    info_id = editable["id"]
    status, out = api("PATCH", f"/v1/appInfos/{info_id}", {
        "data": {"type": "appInfos", "id": info_id,
                 "relationships": {"primaryCategory": {"data": {
                     "type": "appCategories", "id": "MUSIC"}}}}})
    print("primary category set to Music" if status == 200
          else f"::warning::category ({status}): {out}")

    status, out = api("GET", f"/v1/appInfos/{info_id}/appInfoLocalizations")
    locs = out.get("data", []) if status == 200 else []
    loc = next((l for l in locs if l["attributes"].get("locale") == "en-US"), None)
    if not loc:
        print("::warning::no en-US app info localization")
        return
    status, out = api("PATCH", f"/v1/appInfoLocalizations/{loc['id']}", {
        "data": {"type": "appInfoLocalizations", "id": loc["id"],
                 "attributes": {"subtitle": SUBTITLE,
                                "privacyPolicyUrl": privacy_url}}})
    print("subtitle + privacy policy URL set" if status == 200
          else f"::warning::app info localization ({status}): {out}")
    return info_id


def version_localization(version_id, support_url, marketing_url):
    status, out = api(
        "GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations")
    locs = out.get("data", []) if status == 200 else []
    loc = next((l for l in locs if l["attributes"].get("locale") == "en-US"), None)
    if not loc:
        status, out = api("POST", "/v1/appStoreVersionLocalizations", {
            "data": {"type": "appStoreVersionLocalizations",
                     "attributes": {"locale": "en-US"},
                     "relationships": {"appStoreVersion": {"data": {
                         "type": "appStoreVersions", "id": version_id}}}}})
        if status != 201:
            fail(f"could not create en-US localization ({status}): {out}")
        loc = out["data"]
    status, out = api(
        "PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", {
            "data": {"type": "appStoreVersionLocalizations", "id": loc["id"],
                     "attributes": {"description": DESCRIPTION,
                                    "keywords": KEYWORDS,
                                    "promotionalText": PROMO,
                                    "supportUrl": support_url,
                                    "marketingUrl": marketing_url}}})
    print("version metadata set" if status == 200
          else f"::warning::version metadata ({status}): {out}")
    return loc["id"]


def age_rating(app_info_id):
    # The age rating declaration hangs off the app info, not the version.
    status, out = api(
        "GET", f"/v1/appInfos/{app_info_id}/ageRatingDeclaration")
    decl = out.get("data") if status == 200 else None
    if not decl:
        print(f"::warning::no age rating declaration found ({status}): {out}")
        return
    attrs = {k: "NONE" for k in [
        "alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated",
        "horrorOrFearThemes", "matureOrSuggestiveThemes",
        "medicalOrTreatmentInformation", "profanityOrCrudeHumor",
        "sexualContentGraphicAndNudity", "sexualContentOrNudity",
        "violenceCartoonOrFantasy", "violenceRealistic",
        "violenceRealisticProlongedGraphicOrSadistic",
        "gunsOrOtherWeapons"]}
    # The 2025+ additions are booleans (per API type errors).
    attrs.update({k: False for k in [
        "gambling", "unrestrictedWebAccess", "lootBox",
        "healthOrWellnessTopics", "advertising", "messagingAndChat",
        "userGeneratedContent", "ageAssurance", "parentalControls"]})
    status, out = api("PATCH", f"/v1/ageRatingDeclarations/{decl['id']}", {
        "data": {"type": "ageRatingDeclarations", "id": decl["id"],
                 "attributes": attrs}})
    print("age rating set (everything NONE -> 4+)" if status == 200
          else f"::warning::age rating ({status}): {out}")


def upload_screenshots(loc_id):
    for display_type, directory in SCREENSHOT_SETS:
        status, out = api(
            "GET", f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")
        sets = out.get("data", []) if status == 200 else []
        existing = next((s for s in sets
                         if s["attributes"].get("screenshotDisplayType") == display_type), None)
        if existing:
            status, out = api(
                "GET", f"/v1/appScreenshotSets/{existing['id']}/appScreenshots?limit=1")
            if out.get("data"):
                print(f"{display_type}: screenshots already uploaded — skipping")
                continue
            set_id = existing["id"]
        else:
            status, out = api("POST", "/v1/appScreenshotSets", {
                "data": {"type": "appScreenshotSets",
                         "attributes": {"screenshotDisplayType": display_type},
                         "relationships": {"appStoreVersionLocalization": {
                             "data": {"type": "appStoreVersionLocalizations",
                                      "id": loc_id}}}}})
            if status != 201:
                print(f"::warning::screenshot set {display_type} ({status}): {out}")
                continue
            set_id = out["data"]["id"]

        for name in sorted(os.listdir(directory)):
            path = os.path.join(directory, name)
            data = open(path, "rb").read()
            status, out = api("POST", "/v1/appScreenshots", {
                "data": {"type": "appScreenshots",
                         "attributes": {"fileName": name, "fileSize": len(data)},
                         "relationships": {"appScreenshotSet": {"data": {
                             "type": "appScreenshotSets", "id": set_id}}}}})
            if status != 201:
                print(f"::warning::reserve {name} ({status}): {out}")
                continue
            shot = out["data"]
            for op in shot["attributes"]["uploadOperations"]:
                chunk = data[op["offset"]:op["offset"] + op["length"]]
                req = urllib.request.Request(
                    op["url"], data=chunk, method=op["method"])
                for header in op.get("requestHeaders", []):
                    req.add_header(header["name"], header["value"])
                urllib.request.urlopen(req).read()
            status, out = api("PATCH", f"/v1/appScreenshots/{shot['id']}", {
                "data": {"type": "appScreenshots", "id": shot["id"],
                         "attributes": {"uploaded": True,
                                        "sourceFileChecksum":
                                            hashlib.md5(data).hexdigest()}}})
            print(f"uploaded {display_type}/{name}" if status == 200
                  else f"::warning::commit {name} ({status}): {out}")


def set_free_price(app_id):
    status, out = api(
        "GET", f"/v1/apps/{app_id}/appPricePoints?filter[territory]=USA&limit=200")
    points = out.get("data", []) if status == 200 else []
    free = next((p for p in points
                 if p["attributes"].get("customerPrice") in ("0.0", "0.00", "0")), None)
    if not free:
        print(f"::warning::could not find the free price point ({status}); "
              f"set price to Free (0) in App Store Connect -> Pricing")
        return
    point_id = free["id"]
    status, out = api("POST", "/v1/appPriceSchedules", {
        "data": {"type": "appPriceSchedules",
                 "relationships": {
                     "app": {"data": {"type": "apps", "id": app_id}},
                     "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                     "manualPrices": {"data": [{"type": "appPrices",
                                                "id": "${price}"}]}},
                 },
        "included": [{"type": "appPrices", "id": "${price}",
                      "attributes": {"startDate": None},
                      "relationships": {"appPricePoint": {"data": {
                          "type": "appPricePoints", "id": point_id}}}}]})
    if status == 201:
        print("price set to Free")
    elif status == 409 and "already" in str(out).lower():
        print("price schedule already set")
    else:
        print(f"::warning::pricing ({status}): {out} — set Free in ASC UI")


def set_copyright_and_rights(app_id, version_id):
    status, out = api("PATCH", f"/v1/appStoreVersions/{version_id}", {
        "data": {"type": "appStoreVersions", "id": version_id,
                 "attributes": {"copyright": "© 2026 Andrew Callahan"}}})
    print("copyright set" if status == 200
          else f"::warning::copyright ({status}): {out}")
    status, out = api("PATCH", f"/v1/apps/{app_id}", {
        "data": {"type": "apps", "id": app_id,
                 "attributes": {"contentRightsDeclaration":
                                "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}})
    print("content rights declared (no third-party content)" if status == 200
          else f"::warning::content rights ({status}): {out}")


def publish_privacy_labels(app_id):
    """App Privacy 'Data Not Collected', then publish the answers."""
    status, out = api("POST", "/v1/appDataUsages", {
        "data": {"type": "appDataUsages",
                 "relationships": {
                     "app": {"data": {"type": "apps", "id": app_id}},
                     "dataProtection": {"data": {
                         "type": "appDataUsageDataProtections",
                         "id": "DATA_NOT_COLLECTED"}}}}})
    if status == 201:
        print("privacy declaration created: Data Not Collected")
    elif status == 409:
        print("privacy declaration already present")
    else:
        print(f"::warning::privacy declaration ({status}): {out}")
    status, out = api("GET", f"/v1/apps/{app_id}/dataUsagePublishState")
    state = out.get("data") if status == 200 else None
    if not state:
        print(f"::warning::could not read privacy publish state ({status}): {out}")
        return
    if state["attributes"].get("published"):
        print("privacy answers already published")
        return
    status, out = api("PATCH", f"/v1/appDataUsagesPublishState/{state['id']}", {
        "data": {"type": "appDataUsagesPublishState", "id": state["id"],
                 "attributes": {"published": True}}})
    print("privacy answers PUBLISHED" if status == 200
          else f"::warning::privacy publish ({status}): {out} — publish in "
               f"ASC UI: App Privacy -> Data Not Collected -> Publish")


def attach_build(app_id, version_id, build_number):
    status, out = api("GET", f"/v1/builds?filter[app]={app_id}"
                             f"&filter[version]={build_number}")
    builds = [b for b in out.get("data", [])
              if b["attributes"].get("processingState") == "VALID"] \
        if status == 200 else []
    if not builds:
        print(f"::warning::no processed build {build_number} found")
        return
    status, out = api("PATCH", f"/v1/appStoreVersions/{version_id}/relationships/build",
                      {"data": {"type": "builds", "id": builds[0]["id"]}})
    print(f"attached build {build_number}" if status in (200, 204)
          else f"::warning::attach build ({status}): {out}")


def review_details(version_id, phone, email):
    status, out = api(
        "GET", f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail")
    detail = out.get("data") if status == 200 else None
    attrs = {"contactFirstName": os.environ.get("REVIEW_CONTACT_FIRST", "Andrew"),
             "contactLastName": os.environ.get("REVIEW_CONTACT_LAST", "Callahan"),
             "contactPhone": phone, "contactEmail": email,
             "demoAccountRequired": False, "notes": REVIEW_NOTES}
    if detail:
        status, out = api("PATCH", f"/v1/appStoreReviewDetails/{detail['id']}", {
            "data": {"type": "appStoreReviewDetails", "id": detail["id"],
                     "attributes": attrs}})
        ok = status == 200
    else:
        status, out = api("POST", "/v1/appStoreReviewDetails", {
            "data": {"type": "appStoreReviewDetails", "attributes": attrs,
                     "relationships": {"appStoreVersion": {"data": {
                         "type": "appStoreVersions", "id": version_id}}}}})
        ok = status == 201
    print("review contact details set" if ok
          else f"::warning::review details ({status}): {out}")


def submit(app_id, version_id):
    status, out = api(
        "GET", f"/v1/reviewSubmissions?filter[app]={app_id}&filter[state]=READY_FOR_REVIEW")
    subs = out.get("data", []) if status == 200 else []
    if not subs:
        status, out = api("POST", "/v1/reviewSubmissions", {
            "data": {"type": "reviewSubmissions",
                     "attributes": {"platform": "IOS"},
                     "relationships": {"app": {"data": {
                         "type": "apps", "id": app_id}}}}})
        if status != 201:
            print(f"::warning::could not create review submission ({status}): {out}")
            return
        subs = [out["data"]]
    sub_id = subs[0]["id"]
    status, out = api("POST", "/v1/reviewSubmissionItems", {
        "data": {"type": "reviewSubmissionItems",
                 "relationships": {
                     "reviewSubmission": {"data": {
                         "type": "reviewSubmissions", "id": sub_id}},
                     "appStoreVersion": {"data": {
                         "type": "appStoreVersions", "id": version_id}}}}})
    if status == 201:
        print("version added to review submission")
    else:
        print(f"::warning::add version to submission ({status}): {out}")
    status, out = api("PATCH", f"/v1/reviewSubmissions/{sub_id}", {
        "data": {"type": "reviewSubmissions", "id": sub_id,
                 "attributes": {"submitted": True}}})
    if status == 200:
        print("SUBMITTED FOR APP REVIEW 🎉")
    else:
        print(f"::warning::final submit blocked ({status}): {out}")
        print("Most likely remaining step: complete the App Privacy "
              "questionnaire in App Store Connect (App Privacy -> Get "
              "Started -> 'Data Not Collected' -> Publish), then re-run "
              "this workflow.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bundle-id", required=True)
    ap.add_argument("--version", default="1.0")
    ap.add_argument("--build", default="8")
    ap.add_argument("--submit", default="true")
    args = ap.parse_args()

    base = "https://andrewdotcallahan.github.io/Elliot-drum"
    phone = os.environ.get("REVIEW_CONTACT_PHONE", "")
    email = "andrewdotcallahan@gmail.com"

    app_id = find_app(args.bundle_id)
    print(f"app id: {app_id}")
    version_id = ensure_version(app_id, args.version)
    info_id = set_app_info(app_id, f"{base}/privacy.html")
    loc_id = version_localization(version_id, f"{base}/support.html", base)
    if info_id:
        age_rating(info_id)
    upload_screenshots(loc_id)
    set_free_price(app_id)
    set_copyright_and_rights(app_id, version_id)
    publish_privacy_labels(app_id)
    attach_build(app_id, version_id, args.build)
    if phone:
        review_details(version_id, phone, email)
    else:
        print("::warning::REVIEW_CONTACT_PHONE not set; review details skipped")
    if args.submit.lower() == "true":
        submit(app_id, version_id)


if __name__ == "__main__":
    main()
