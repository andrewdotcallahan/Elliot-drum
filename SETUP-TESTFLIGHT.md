# TestFlight setup — push to GitHub, app appears on your iPad

This guide takes you from "I have this code on GitHub" to "every push to
`main` automatically becomes a new build on my iPad via TestFlight" — with
**no Mac involved**. GitHub's servers do the building and signing.

You do this setup **once**. It takes about an hour of clicking, plus a
1–2 day wait for Apple to approve your developer enrollment.

What you'll end up with:

```
git push → GitHub Actions (a rented Mac in the cloud) builds & signs the app
         → uploads it to Apple's TestFlight
         → the TestFlight app on your iPad offers the update
```

---

## Step 1 — Enroll in the Apple Developer Program ($99/year)

1. Go to <https://developer.apple.com/programs/enroll/>.
2. Sign in with your Apple ID (the same one you use on the iPad is fine)
   and enroll as an **Individual**.
3. Pay the $99 annual fee.
4. Wait for the approval email. This usually takes **24–48 hours**;
   nothing below works until it arrives.

## Step 2 — Register the app's bundle ID

The bundle ID is the app's unique technical name. This project uses
`com.andrewhq.babyband` (already set in the Xcode project).

1. Go to <https://developer.apple.com/account> and sign in.
2. Click **Certificates, Identifiers & Profiles** → **Identifiers**.
3. Click the blue **+** button.
4. Choose **App IDs** → **Continue** → **App** → **Continue**.
5. Fill in:
   - **Description:** `BabyBand`
   - **Bundle ID:** select **Explicit** and type `com.andrewhq.babyband`
6. Leave every capability checkbox **unchecked** (the app needs none).
7. Click **Continue** → **Register**.

> **If Apple says the bundle ID is already in use:** pick another one, e.g.
> `com.yourlastname.babyband`, register that instead, and change the two
> `PRODUCT_BUNDLE_IDENTIFIER = com.andrewhq.babyband;` lines in
> `BabyBand.xcodeproj/project.pbxproj` to match (it appears twice — once
> for Debug, once for Release). Any plain text editor works.

## Step 3 — Create the app record in App Store Connect

1. Go to <https://appstoreconnect.apple.com> and sign in.
2. Click **Apps** → the blue **+** → **New App**.
3. Fill in:
   - **Platforms:** iOS
   - **Name:** `BabyBand` — app names are unique across the whole App
     Store, so if it's taken try `BabyBand for Kids`, `Our BabyBand`, or
     anything you like. This name is only what shows in TestFlight; it
     doesn't have to match the code.
   - **Primary Language:** English (or yours)
   - **Bundle ID:** pick `com.andrewhq.babyband` from the dropdown
     (it's there because of Step 2).
   - **SKU:** anything, e.g. `babyband-001`. It's an internal label.
   - **User Access:** Full Access.
4. Click **Create**.

You do **not** need to fill in screenshots, descriptions, or pricing —
those are only required for a public App Store release, not TestFlight.

## Step 4 — Create an App Store Connect API key

This key is what lets GitHub upload builds on your behalf.

1. Still in App Store Connect, click **Users and Access** (top nav).
2. Click the **Integrations** tab → **App Store Connect API** →
   **Team Keys**.
3. Click **+** (Generate API Key).
4. **Name:** `GitHub Actions`. **Access (role):** **Admin**.
   (Admin is required: xcodebuild's cloud-managed signing creates the
   distribution certificate and provisioning profile via this key, and
   an App Manager key gets "Cloud signing permission error" there.
   App Manager suffices only for uploading once signing assets exist.)
5. Click **Generate**.
6. Click **Download API Key** and save the `AuthKey_XXXXXXXXXX.p8` file.
   **You can only download it ONCE.** Store it somewhere safe and private
   (a password manager is ideal). **Never** put it in the git repo.
7. Write down two values shown on that page:
   - **Key ID** (10 characters, also in the filename, e.g. `A1B2C3D4E5`)
   - **Issuer ID** (long UUID at the top of the Team Keys page)

## Step 5 — Find your Team ID

1. Go to <https://developer.apple.com/account>.
2. Scroll to **Membership details**.
3. Copy the **Team ID** — 10 characters like `ABCDE12345`.

## Step 6 — Add the four secrets to GitHub

1. Open your repo on GitHub → **Settings** (repo settings, not your
   account) → **Secrets and variables** → **Actions**.
2. Click **New repository secret** four times, creating exactly these
   names (spelling matters):

   | Secret name             | Value                                        |
   |-------------------------|----------------------------------------------|
   | `APPLE_TEAM_ID`         | Team ID from Step 5, e.g. `ABCDE12345`       |
   | `ASC_KEY_ID`            | Key ID from Step 4, e.g. `A1B2C3D4E5`        |
   | `ASC_ISSUER_ID`         | Issuer ID (UUID) from Step 4                 |
   | `ASC_API_KEY_P8_BASE64` | the `.p8` file, base64-encoded — see below   |

   To base64-encode the `.p8` file:
   - **On a Mac:** `base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy`
     (it's now on your clipboard — paste it into the secret).
   - **On Linux:** `base64 -w0 AuthKey_XXXXXXXXXX.p8`
   - **On Windows (PowerShell):**
     `[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXXXXXXXX.p8"))`

   Paste the whole output (one long line of letters/numbers) as the value.

## Step 7 — Run the pipeline

1. Push any commit to `main` — or go to the repo's **Actions** tab, pick
   **TestFlight** on the left, and click **Run workflow**.
2. Watch it run (Actions tab → the running job). A build takes roughly
   **10–15 minutes**. The very first run can take a few minutes longer
   while Apple creates your signing certificate and provisioning profile
   automatically (that's the "cloud-managed signing" doing its job).
3. When it's green, go to App Store Connect → **Apps** → **BabyBand** →
   **TestFlight** tab. The build appears there, sometimes after a short
   "Processing" period (5–30 minutes).
4. Export compliance: the project already declares that it uses no
   non-exempt encryption (`ITSAppUsesNonExemptEncryption = NO`), so builds
   should go straight to "Ready to Test" without asking you the encryption
   question. If ASC still shows **Missing Compliance** on a build, click
   **Manage**, answer **None of the algorithms mentioned above**, and save.

## Step 8 — Install on the iPad

1. In App Store Connect → BabyBand → **TestFlight** → **Internal Testing**
   (left sidebar) → **+** to create a group, name it e.g. `Family`.
2. Click **+** next to Testers and add yourself (your Apple ID email).
   You can add up to 100 internal testers; add other family members'
   Apple IDs the same way.
3. On the iPad: install the **TestFlight** app from the App Store, sign
   in with the same Apple ID, and accept the emailed invite (or it just
   appears in TestFlight).
4. Tap **Install**. Done.

From now on: **every push to `main` produces a new build**, and TestFlight
on the iPad will offer the update automatically (enable automatic updates
in TestFlight's settings for the app). Each build is installable for
**90 days**; since every push creates a fresh build, in practice it never
expires as long as you push occasionally — or just tap **Run workflow**
in the Actions tab now and then.

---

## Troubleshooting

**"App name is already being used"** (Step 3)
: App Store names are globally unique. Pick a variant (`BabyBand for
  Kids`, `HQ BabyBand`, ...). Only the TestFlight listing shows this name.

**"Bundle ID is not available" / already registered** (Step 2)
: Someone else owns it. Choose a different one and update the two
  `PRODUCT_BUNDLE_IDENTIFIER` lines in
  `BabyBand.xcodeproj/project.pbxproj` — then register the new ID
  (Step 2) and create the app record with it (Step 3).

**Workflow fails with an authentication / 401 / "not authorized" error**
: Re-check all four secrets for typos and stray whitespace. Make sure the
  API key's role is **App Manager** (a Developer-role key cannot upload
  builds). If you regenerated the key, update both `ASC_KEY_ID` and
  `ASC_API_KEY_P8_BASE64`.

**Fails at archive with "No profiles for 'com.andrewhq.babyband' were found"**
: Usually one of: the bundle ID was never registered (Step 2), the
  `APPLE_TEAM_ID` secret is wrong, or the app record doesn't exist yet
  (Step 3). Fix and re-run. On a brand-new account the first run can also
  fail while Apple's systems catch up — waiting 10 minutes and re-running
  genuinely fixes this surprisingly often.

**Build uploads but never leaves "Processing" / doesn't appear**
: Processing can take up to an hour on busy days. Also check the email
  tied to your Apple ID — Apple mails you if a build is rejected during
  processing (the message says why).

**Build shows "Missing Compliance" in TestFlight**
: See Step 7.4 — click Manage, answer the encryption question once. The
  committed project setting should prevent this for subsequent builds.

**Workflow fails selecting Xcode**
: GitHub occasionally reshuffles the Xcode versions installed on its
  runner images. The workflow picks the newest Xcode 16.x automatically;
  if the `macos-15` image someday drops Xcode 16 entirely, edit
  `.github/workflows/testflight.yml` and adjust the `Xcode_16*` pattern
  (see the runner image notes at
  <https://github.com/actions/runner-images> for what's installed).

**"Your session has expired" or 2FA prompts**
: You never need to put your Apple ID password anywhere in this pipeline —
  the API key replaces it. If some step asks for your password, you're
  in the wrong flow; re-read the step.

## Security notes

- The `.p8` API key can upload builds and edit your App Store apps.
  Treat it like a password: keep the original file in a password manager,
  never commit it, never paste it into chat/email.
- The four values live only in GitHub Actions **encrypted secrets**; the
  workflow never prints them and deletes the key file from the build
  machine when it finishes.
- If you ever suspect the key leaked: App Store Connect → Users and
  Access → Integrations → revoke the key, generate a new one, and update
  the two secrets.
