# Physical-device acceptance checklist

Record the device model, iOS version, app build and package version. Mark each item Pass, Fail or N/A, with notes. **None of these checks has been performed yet.**

Device: ______  iOS: ______  App build: ______  Package: ______  Tester: ______  Date: ______

## A. Installation and content

- [ ] The app installs and launches with no content installed. It shows "No content installed" and links to Content status.
- [ ] A signed package imports from Files, and Content status shows the package version, publication date, signing key and import date ("not a currency date").
- [ ] A package signed with an untrusted key is rejected, with a clear message, and the previous package stays in use.
- [ ] A truncated or altered package is rejected, and the previous package stays in use.
- [ ] Rolling back restores the previous package.

## B. Airplane mode after restarting the phone

1. Turn on **Airplane Mode** and confirm Wi-Fi and Bluetooth are off.
2. **Restart the iPhone** (power off, then on), unlock it, and open Police HQ.

- [ ] The home screen shows "What are you dealing with?" and "Describe the situation, or choose a guide."
- [ ] The Statutes browser lists federal, constitutional, provincial and municipal sources. The municipal filter works for Peel Region, Brampton and Mississauga.
- [ ] Open the Criminal Code and go to section **495(1)**. The header shows "Federal — Canada", "Current to …", "Not verified against publisher" and the unofficial-reproduction notice.
- [ ] **Search this document** for "warrant". Match navigation (up and down) moves between highlighted matches in that document only.
- [ ] **Search all sources** for "trespass". Results come from several sources, each with its jurisdiction label.
- [ ] Open the original document (QuickLook) for a federal PDF and for an Ontario Word file.
- [ ] Authorities hub: all six categories appear, with icons and text labels. A common-law card (Investigative detention) says the source is not installed.
- [ ] Rights hub: each stage lists rights. Youth items are labelled.
- [ ] Cautions library: each entry shows **"Approved wording not installed."** and what's missing, at every explanation level.
- [ ] Start a situation, set the incident date and city, and set the stage to Arrest. "What needs clarification" appears first, the limitations banner is visible, and the checklists are not completed.
- [ ] Record a checklist item as complete (it needs a name), and mark one Not applicable (it needs a reason).
- [ ] Record a communication. The checklist status doesn't change, and the record has no "understood" or "waived" field.
- [ ] Penalties panel for Speeding: enter 25 km/h over. The statutory calculation shows $112.50 with its source. Set fine, surcharge, costs and points show "Not installed", and the total shows **"Total cannot be verified."**
- [ ] Force-quit and reopen. The situation, bookmarks and saved searches are still there.
- [ ] The app switcher shows the privacy shield, not situation content.
- [ ] Settings › On-device assistance shows availability honestly. With assistance off or unavailable, every workflow above still works.

## C. On-device model (supported devices only, iOS 26+)

- [ ] With Apple Intelligence on and the model downloaded, "Propose facts" produces proposals marked "not used until you confirm". Rejecting one removes it, and confirming one asks for its provenance.
- [ ] In airplane mode, assistance either works on device or reports that it is unavailable. It never asks for a network connection.

## D. Accessibility and appearance

- [ ] Dynamic Type at the largest accessibility size: text wraps, and controls stay usable.
- [ ] VoiceOver reads tab names, shortcut tiles, status badges (with text, not just colour), quotations and citation links.
- [ ] Light and dark appearance are both legible.

## E. Privacy

- [ ] Settings › Erase all local records removes situations, bookmarks and saved searches.
- [ ] Retention: with the retention set to 1 day and a situation older than that, reopening the app deletes it. This can be tested with the device clock if your policy allows.
- [ ] An export with a passphrase can't be imported with a wrong passphrase. Re-importing with the right one keeps the recorded package version.
