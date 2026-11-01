# Privacy and local records

## What is stored, and where

| Data | Location | Protection |
|---|---|---|
| Situations (narrative, facts, evidence notes, timeline, checklists, analyses) | `Application Support/Scenarios/*.phqs` | Each file is AES-GCM encrypted with a 256-bit key held in the Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). Files are written with `NSFileProtectionComplete`. |
| Bookmarks and saved searches | `Application Support/*.enc` | Same key and file protection. |
| Settings (explanation level, default city, retention, toggles, update address) | UserDefaults | Not encrypted. No situation content is stored here. |
| Content package (published law) | `Application Support/Content/` | `NSFileProtectionCompleteUntilFirstUserAuthentication`. Excluded from backups (it can be re-imported). |

## What the app does not do

- **No external transmission:** situation content isn't put in analytics, logs, notifications, crash payloads or network requests.
- **No services:** no analytics SDK, no remote crash reporting, no accounts, no server.
- **No cloud inference.** The optional language model runs only on the device.
- **Network:** only a user-initiated content download from an `https://` address the user entered.
- **Excluded features:** biometric identification, predictive policing, demographic risk scoring, automated credibility scoring, operational tactics and CPIC/RMS integration.

## App switcher

When the app is not active, a full-screen shield covers its content, so the app-switcher snapshot doesn't show situation details. Situation views are also marked `privacySensitive()`.

## Backups

**Situations:** excluded from iCloud and computer backups by default. If the user enables *Include situations in device backups*, the encrypted files are backed up, but the Keychain key is device-only, so those files can't be decrypted on another device.

## Retention and deletion

- **Retention:** situations not updated within the retention period (default 30 days, configurable from 1 to 365) are deleted when the app opens.
- **Manual deletion:** situations can be deleted individually. *Erase all local records* also destroys the Keychain key, which makes any remaining copies unreadable.

**Limits of deletion:** deleting removes the file from the app. Flash storage doesn't guarantee physical erasure, and copies in backups made earlier (if enabled) or in exported files are outside the app's control. Encryption with a device-only key is the main protection.

## Export and re-import

Export creates a `.phqscenario` file:

- **With a passphrase (12+ characters):** encrypted with PBKDF2-SHA256 (600,000 iterations) and AES-GCM.
- **Without one:** readable JSON, and the app shows a warning.

Re-import preserves the situation's id, facts, provenance, source versions and audit trail, and adds an audit entry. Once a file is exported it is outside the app's protection. Anyone with the file, plus the passphrase if one was set, can read it.

## Audit log

Each situation keeps an append-only list of actions (created, fact corrected, checklist recorded, reassessed and so on). It is ordinary local data. **It is not immutable or tamper-proof**, and the app doesn't claim it is.

## Development data

All test fixtures and training scenarios are fictional. Don't commit real situations, personal information or restricted service material to the repository.
