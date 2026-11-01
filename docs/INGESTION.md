# Ingestion

The ingestion tools run on a **development computer**. They need Python 3.11+ and these system tools:

- poppler (`pdftotext`, `pdfinfo`, `pdftoppm`)
- LibreOffice (`soffice`), to convert DOC to DOCX
- Tesseract, for OCR

The iPhone app never runs these tools and needs no server to use their output. Uploaded documents are treated as data: nothing inside a document is ever read as an instruction (see `tests/test_pipeline.py::test_instruction_like_text_in_a_source_is_stored_as_text_only`).

```bash
scripts/build_content.sh <uploads-dir> <signing-key> <key-id> <package-version>
```

The script runs six steps, described below.

## 1. Convert

LibreOffice converts legacy `.doc` files (the Ontario e-Laws Word exports) to `.docx` in `build/converted/`. Originals are never modified.

## 2. Inventory (`phq_ingest.inventory`)

For every upload, the inventory records:

- **Basics:** SHA-256, size, format and page count.
- **Embedded metadata.**
- **Publisher banners:** the Justice Laws "Current to / Last amended on" banner, the e-Laws "Consolidation Period" and "Last amendment", and reference-conversion banners.
- **Text density and low-text pages.**
- **Bilingual layout detection:** compares English and French markers in the left and right halves of sampled pages.
- **Municipal names printed in the text.**
- **Exact duplicates**, matched by hash.

## 3. Registry (`content/source_registry.json`)

`registry_seed.py` builds one record per distinct source, using metadata taken from the document content: cover pages, e-Laws document properties and by-law numbers printed in the text. Anything known only from a filename is labelled *upload filename (not verified)*.

`content/registry_overrides.json` holds curated corrections, keyed by SHA-256. Each records its basis, for example "by-law number 93-93 printed on the schedule; the consolidated text names the City of Brampton".

Relationships (schedule-of, map-of, sign-for, regulation-under, original-enactment-of) are computed with their basis and a `verified` flag.

Every source starts with:

- `official_url_status: "Not verified"`
- `verification_status: "Not verified"`
- `editorial_review_status: "imported"`

## 4. Extraction and database (`build_db`)

| Publisher family | Method |
|---|---|
| Justice Laws bilingual PDFs | English **left column only** (`pdftotext -x 0 -W 306`), so English and French are never interleaved. Pages printed in French only are skipped (they remain in the original); full-width English table pages are read whole. Running headers and the "Current to" footer are removed. Table of provisions, foreword, ENDNOTES, RELATED PROVISIONS and AMENDMENTS NOT IN FORCE are separate regions with their own statuses. Section, subsection, paragraph, subparagraph and clause detection handles marginal notes (including multi-line notes and group headings), section numbers printed in the margin after the first line, roman numeral versus letter ambiguity, definitions, history citations and repealed sections. Words hyphenated at line ends are rejoined only where the joined word appears elsewhere in the document, and letter-spaced text ("w i l l") is repaired the same way. |
| Ontario e-Laws Word | The paragraph styles drive the structure (`section`, `subsection`, `paragraph`, `subpara`, `definition`, `headnote`, `partnum`, `footnoteLeft` and so on). `Y`-prefixed styles are **not yet in force**, and `Pnote` is an editorial annotation; both are stored separately. Amendment citations after the text are split into `history`. Closing words after a list are kept as `[closing]` units, in reading order. |
| Municipal PDFs | Page text is always stored. Running headers and footers that repeat on most pages are removed. Section numbering (1., 1.1, (a), (1)) and definitions are parsed heuristically and labelled `heuristic-structure`. Image-only pages are OCR'd with Tesseract and labelled *OCR — unverified*. Reference-conversion banners are kept as annotations, never as operative text. |

Original files are copied byte-for-byte into `originals/` (hash-checked) so the app can show them through QuickLook.

### Quality checks (`quality.py`)

The checks are automated: duplicate numbering paths, other parser warnings, section-number regressions, possible truncation against the source text layer, and image or OCR pages. Each source gets one of these quality values:

- `automated-checks-passed`
- `passed-with-warnings`
- `heuristic-structure`
- `image-only`
- `unusable`

**Passing automated checks is not "extraction verified".** That state needs a recorded human comparison against the original.

`trusted_for_guidance` is set only for publisher-issued sources that pass the checks. Municipal sources, reference conversions, maps and signs are reference material until someone verifies them.

### Guides and penalties (`guides.py`)

These are compiled into the database. The build **fails** if:

- any citation doesn't resolve to an installed, in-force provision
- an `excerpt_contains` string, threshold quote, element quote or checklist quote isn't found verbatim in the installed text
- a guide claims approval without a matching approved review record
- an amount is supplied for a non-verified penalty component, or a verified amount's text can't be found in the cited provision

## 5. Coverage report

`phq_ingest.coverage` writes `docs/COVERAGE_REPORT.md` and a JSON version. They cover totals by jurisdiction and quality, unusable, image-only and reference-conversion sources, duplicates, gaps, and every source with its consolidation date.

## 6. Sign and verify

See [UPDATES.md](UPDATES.md).

## Adding or replacing sources

1. **Add the file.** Put the new or updated file in your uploads folder and rerun the script. A changed file has a new hash, so it becomes a new registry record. Keep or retire the old record deliberately; a changed file is not a verified change in the law.
2. **Fix the metadata.** Correct any metadata in `registry_overrides.json` and record the basis for each change.
3. **Record verification.** When you have compared an extraction against the original, set the source's `editorial_review_status` to `extraction-verified` in the overrides, with the reviewer and date in `quality_notes`. Then municipal material can be considered for guided analysis.

## Results for the 2026-11-01 uploads

219 files were uploaded: 33 legacy DOC, 185 PDF and 1 TXT (the requirements). After removing 20 exact duplicate uploads, that's 198 distinct sources. All 23 federal PDFs were detected as bilingual two-column. Results by quality:

| Quality | Sources |
|---|---|
| Automated checks passed | 52 |
| Passed with warnings | 4 |
| Heuristic structure (municipal) | 135 |
| Image only (maps and signs) | 7 |

See [COVERAGE_REPORT.md](COVERAGE_REPORT.md).
