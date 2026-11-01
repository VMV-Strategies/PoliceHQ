# Content packages, signing and updates

## Keys

```bash
cd tools
python3 -m phq_ingest.package keygen --out-private ~/phq-keys/signing.key --out-public ../content/trusted_keys/<key-id>.pub
```

- **Private key:** keep it **outside the repository**, for example in a password manager or HSM-backed storage. `.gitignore` excludes `*.key`.
- **Public key:** add it to `App/Resources/TrustedKeys.txt` (base64, one per line), then rebuild the app.
- **Development key:** this repository ships the public key `phq-dev-2026`, generated on 2026-11-01 for the development package. Replace it with your own before any distribution, and remove keys you no longer trust.
- **Rotation:** add the new public key and ship an app build that trusts both keys. Sign new packages with the new key, then remove the old key in a later build.

## Building and verifying

```bash
python3 -m phq_ingest.package build --src build/package --key ~/phq-keys/signing.key --key-id <key-id> \
    --version 2026.11.01 --min-app 1.0 --out dist/PoliceHQ-content-2026.11.01.phqpkg
python3 -m phq_ingest.package verify --pkg dist/PoliceHQ-content-2026.11.01.phqpkg --public content/trusted_keys/*.pub
```

**What verification establishes:** the package was produced by the holder of a trusted signing key, and no file has been altered or added since signing.

**What it does not establish:** that the law in it is correct, current, complete or reviewed.

## Installing on the iPhone

There are three ways to install a package:

- **From Files:** Settings › Content status › Import package. This works without internet, for example with a file copied over AirDrop or from a cable-connected computer.
- **From a configured address:** Download update from configured address. This uses an `https://` address the user typed, and runs only when the user taps it.
- **Bundled:** place a `.phqpkg` in `App/Resources/BundledContent/` before building. It's verified on first launch like any other package.

Installation is atomic:

1. Verify the signature, format, schema, minimum app version, paths and every hash.
2. Extract to `staging-*`.
3. Open the database as a smoke test.
4. Swap: `current` becomes `previous`, and `staging` becomes `current`.

If anything fails, `current` is untouched and the user is told the last usable package is still in use. **Roll back** swaps `previous` and `current`. Saved situations keep the package and source versions recorded when they were analyzed, and are only reassessed when the user asks.

## Checking official sources (development side)

```bash
python3 -m phq_ingest.update_check --registry content/source_registry.json --out build/update_report.json
```

The checker works as follows:

- **What it fetches:** the recorded official URL. If none is recorded, it fetches a clearly labelled candidate: e-Laws URLs derived from the e-Laws file code, or the source URL printed inside a reference conversion.
- **How it fetches:** with plain HTTPS GETs, one at a time, with a delay and a descriptive User-Agent. Respect each publisher's terms and access restrictions.
- **What it compares:** the "Current to", "Last amended" and "Consolidation Period" dates on the page.
- **What it reports:** *Dates match*, *Possible change — review required*, or *Not verified* (when no URL is recorded, the fetch failed, or it was blocked). A failed check is never treated as "no change".

**It never changes content.** A changed file or page is not a verified change in operative law. The process for each change is:

1. Download the new official version and add it to the uploads.
2. Rebuild, and read the coverage and quality reports.
3. Have a person compare the old and new text of the affected provisions.
4. Update the guides that cite changed provisions, with new versions and new reviews.
5. Bump the package version, sign it and distribute it.

Publishers to check:

- Justice Laws (federal)
- Ontario e-Laws
- the Regional Municipality of Peel
- the City of Brampton
- the City of Mississauga
- official court websites, for decisions
- official Ontario sources for set fines, surcharge, costs and demerit points

In this build environment, outbound access was limited, so no official-source verification was performed. Every source is *Not verified*.
