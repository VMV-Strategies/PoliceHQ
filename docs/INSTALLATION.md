# Installing Police HQ on an iPhone

Cloning the repository does **not** install the app. You build it with Xcode on a Mac and install it through Apple's signing and distribution systems.

## Requirements

| Item | Requirement |
|---|---|
| Mac | macOS with **Xcode 26 or later**. Since 28 April 2026, App Store Connect uploads must be built with Xcode 26 or later and the iOS 26 SDK ([Apple: upcoming requirements](https://developer.apple.com/news/upcoming-requirements/)). |
| iPhone | **iOS 17.0 or later** for the app, search, guides, situations and penalties. |
| Optional on-device model | **iOS 26 or later** on a device that supports Apple Intelligence, with Apple Intelligence turned on and the model downloaded. Apple lists: iPhone 15 Pro, 15 Pro Max, 16, 16 Plus, 16 Pro, 16 Pro Max, 16e, 17, 17 Pro, 17 Pro Max, iPhone Air and 17e ([Apple Support](https://support.apple.com/en-gb/guide/iphone/aside/iph275f4d617/26/ios/26)). Region and language availability can also apply. On other devices the app shows that assistance is unavailable, and every core function still works. |
| Storage | About 100 MB for the development content package (an 89 MB database plus original documents), plus the app itself. |
| Tools | [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the project from `project.yml`. |

Your iPhone model wasn't specified. To confirm on-device model support, check it against the list above. Nothing else in the app depends on the model.

## 1. Generate the project

```bash
brew install xcodegen
cd police-hq
xcodegen generate
open PoliceHQ.xcodeproj
```

In the PoliceHQ target's *Signing & Capabilities*, choose your team. Change the bundle identifier from `ca.example.policehq.app` to one you control.

## 2. Development install, over a cable or network

1. Turn on **Developer Mode** on the iPhone (Settings › Privacy & Security › Developer Mode) when prompted.
2. Connect the iPhone, select it as the run destination, and press Run.
3. With a **free Apple ID (Personal Team)**, Xcode can install on your own device, but with significant limitations. The app stops launching after a short period (commonly 7 days) and has to be reinstalled from Xcode. See Apple's [Choosing a Membership](https://developer.apple.com/support/compare-memberships/).
4. With an **Apple Developer Program** membership, development provisioning profiles last longer, but they still have expiry dates and need renewing in Xcode.

## 3. TestFlight

This needs a paid membership.

1. Archive the app (Product › Archive) and upload it to App Store Connect.
2. Answer the export-compliance questions. The app uses Apple's encryption APIs (CryptoKit and CommonCrypto) for local data protection and package signature checks.
3. Add internal testers (up to 100 App Store Connect users) or external testers (up to 10,000, after beta review).
4. **TestFlight builds can be tested for up to 90 days** ([Apple: TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview)). After that, testers need a newer build.

## 4. Production distribution

- **App Store:** subject to App Review. Public distribution of a police legal-reference tool needs your organization's approval and a legal review of the content scope.
- **Custom or private distribution** to an organization (for example Apple Business Manager custom apps) or **enterprise** programs: these are governed by Apple's current program terms. Confirm eligibility with Apple and your IT department.
- **Ad hoc:** limited to registered devices. Profiles expire and need renewing.

## 5. Install content

The app installs with no legal content. Provision it separately:

1. Build a signed package (see [INGESTION.md](INGESTION.md) and [UPDATES.md](UPDATES.md)), or use the development package delivered with this build.
2. Make sure the signing public key is in `App/Resources/TrustedKeys.txt` in the build you installed.
3. Copy the `.phqpkg` to the iPhone, for example with AirDrop, Files, or the Finder over a cable.
4. In Police HQ, go to Settings › Content status › **Import package from Files**.

Alternatively, put the package in `App/Resources/BundledContent/` before building, and it's installed on first launch.

## 6. Check offline operation

Follow [DEVICE_ACCEPTANCE_CHECKLIST.md](DEVICE_ACCEPTANCE_CHECKLIST.md), including the airplane-mode-after-restart checks.
