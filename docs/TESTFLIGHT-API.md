# Programmatic TestFlight access

Drift uses Apple's official App Store Connect API. Routine build status, tester
feedback, beta review, and group assignment do not require a browser. The
dependency-free scripts use Node.js 20 or newer; uploading an archive also needs
Xcode on macOS.

## Local credentials

The personal Apple account has a team key with **App Manager** and **Customer
Support** roles. Credentials are kept
outside the repository in `~/.config/drift/app-store-connect/`: the directory is
mode `700`, and `config.json` and the `.p8` file are mode `600`. Never copy the
private key into this repository or command output.

The configuration has `keyId`, `issuerId`, `privateKeyPath`, `appId`, and
`bundleId` fields. CI can supply `ASC_KEY_ID`, `ASC_ISSUER_ID`,
`ASC_PRIVATE_KEY_PATH`, and `ASC_APP_ID` instead of a configuration file.
The app ID is `6809245122`, bundle ID is `best.christopher.drift`, and personal
signing team is `F486BUQ5G3`. Team keys apply to all apps in that personal account;
the App Manager role does not grant user administration.

## Read builds and feedback

Run from the repository root:

```sh
node scripts/app-store-connect.mjs status
node scripts/app-store-connect.mjs feedback
node scripts/app-store-connect.mjs crash-log FEEDBACK_SUBMISSION_ID
```

Output is JSON. `status` returns the app, ten newest builds with processing and
beta states, and tester groups. `feedback` follows all pages and retains comments,
screenshots, device metadata, and related build/tester records. Feedback can
contain private note text or tester details; save reports outside the repository
with restrictive permissions.

Crash feedback covers **tester-submitted** reports and attached logs; it is not
a complete feed of automatically collected crashes in Xcode Organizer.

For another Apple endpoint:

```sh
node scripts/app-store-connect.mjs api GET '/v1/apps/6809245122'
node scripts/app-store-connect.mjs api GET '/v1/betaGroups/f9e45cce-770d-4518-b8fb-60a3eb0e51b5/builds'
```

Requests and pagination are restricted to `https://api.appstoreconnect.apple.com`.
The client signs ten-minute tokens locally and never prints credentials.

## Upload and distribute

First complete the release checks in [RELEASING.md](RELEASING.md), including
the iOS Jank Audit. Archive the normal **Drift** target with the personal team,
using a new build number. The uploader accepts an already validated archive:

```sh
node scripts/upload-testflight.mjs /path/to/Drift.xcarchive --dry-run
node scripts/upload-testflight.mjs /path/to/Drift.xcarchive
```

The dry run verifies the bundle ID, personal signing team, and archive signature
without contacting Apple. Upload uses Xcode's native API-key authentication and
`app-store-connect` export method, preserves the selected build number, and sends
symbols. It does not explicitly assign the build to a group or submit it for
review; existing automatic internal-distribution settings may still apply.

Check `status` after upload. Upload acceptance, processing, beta review, group
assignment, and tester availability are separate stages. An upload success alone
does not establish that testers can install it.

The generic API command also supports explicit `POST`, `PATCH`, and `DELETE`
requests using `--body /path/to/request.json`. These change the live Apple account.
For a release, use Apple's resources in the following order as needed:

1. Set the build's testing notes with `betaBuildLocalizations`.
2. Complete any required export-compliance and beta-review information.
3. Add the exact build ID to the existing Public Beta group's builds relationship:
   `POST /v1/betaGroups/f9e45cce-770d-4518-b8fb-60a3eb0e51b5/relationships/builds`.
   The body is `{"data":[{"type":"builds","id":"BUILD_ID"}]}`.
4. If beta review is required, submit with `POST /v1/betaAppReviewSubmissions`.
   The body is
   `{"data":{"type":"betaAppReviewSubmissions","relationships":{"build":{"data":{"type":"builds","id":"BUILD_ID"}}}}}`.
5. Verify the specific group's builds and the build's external testing state.

Do not assume every release needs a new review submission; read the current
state first. Notifications and external distribution should follow the requested
release scope. The API does not bypass Apple's review.

## CI

Use the same scripts in a CI job. Store the `.p8` contents in the CI secret store,
write them to a temporary file with mode `600`, set the `ASC_` variables above,
and remove the file when the job ends. Read-only API jobs can run without Xcode.
Archive/upload jobs need a macOS runner with Xcode and appropriate signing
certificates/profiles for the personal team, or explicitly configured automatic
provisioning. API access does not itself install a distribution certificate.

No hosted CI job or automatic release trigger is configured by this local setup.
Fastlane can also use the same team key if a broader CI pipeline needs it.

## Verification

```sh
node --test scripts/app-store-connect.test.mjs
```

Initial live verification on September 20, 2026 succeeded for app/build/group and
both feedback endpoints. Build `0.2 (10)` was in external beta testing; feedback
contained one screenshot submission and zero crash submissions. These are a
snapshot, not a current-state guarantee. The upload helper was checked with a
dry run; this setup did not upload or release an app.

References: [Apple API keys](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api),
[TestFlight API](https://developer.apple.com/documentation/appstoreconnectapi/prerelease-versions-and-beta-testers),
[screenshot feedback](https://developer.apple.com/documentation/appstoreconnectapi/beta-feedback-screenshot-submissions),
[crash feedback](https://developer.apple.com/documentation/appstoreconnectapi/beta-feedback-crash-submissions).
