# Testing

## What has actually been run

| Check | Status | Notes |
|---|---|---|
| Python pipeline tests (`tools/tests`, 25 tests) | **Passed** | Run on 2026-11-01 with Python 3.13. 4 of them are integration tests run against the built development database. |
| `scripts/check.sh` (schema copy in sync, JSON validity, Python tests) | **Passed** | |
| Full content build from the 219 uploads | **Completed** | 198 sources and about 106,000 provisions. 58 guides and 101 citations compiled, with every citation and quote verified against installed text. |
| Package signing and verification (Python) | **Passed** | 200 files, Ed25519. Tamper and wrong-key cases are covered by tests. |
| Swift syntax check (all 26 Swift files) | **Passed** | Uses the tree-sitter Swift grammar. This is a **parser-level check only**: it doesn't catch type errors. |
| Swift compilation, `swift test` and the app build | **Not performed** | No Xcode or Swift toolchain was available (the Swift download host was blocked). Run CI or [SETUP.md](SETUP.md) to compile and test. Expect to fix some compile errors on the first build. |
| iOS Simulator and physical-device tests | **Not performed** | Use [DEVICE_ACCEPTANCE_CHECKLIST.md](DEVICE_ACCEPTANCE_CHECKLIST.md). |
| Legal review | **Not performed** | No review records exist. |

## Acceptance tests mapped to code

Swift tests are in `Packages/PoliceHQCore/Tests/PoliceHQCoreTests/AcceptanceTests.swift` (they run against a fictional fixture database). Python tests are in `tools/tests/test_pipeline.py`.

| Requirement | Test |
|---|---|
| Search and source viewing without networking | `SearchAndSourceTests.testSearchAndSourceViewingWorkWithoutNetworking` (a URLProtocol trap counts requests) |
| Searching within one document excludes others | `testSearchWithinOneDocumentExcludesOtherDocuments` |
| Section navigation and correct citation targets | `testSectionNavigationAndCitationTargets`; Python `test_built_db_key_provisions_present` |
| Correct source version and jurisdiction labels | `testJurisdictionAndVersionLabels`, `testHistoricalIncidentsDoNotSilentlyUseLatestLaw` |
| Brampton provisions not applied to Mississauga | `JurisdictionTests.testBramptonProvisionsDoNotApplyToMississauga`; Python `test_built_db_brampton_and_mississauga_are_separate` |
| Saved situations reopen after restart | `ScenarioStoreTests.testSavedSituationsReopenAfterRestart` |
| Missing facts remain unknown | `AnalysisTests.testMissingFactsRemainUnknown`, `testSupportedOnlyByAllegationIsFlagged` |
| Unsupported model citations rejected | `AssistantValidationTests.testUnsupportedModelCitationsAreRejected` |
| Uploaded-document instructions don't override app rules | `testUploadedDocumentInstructionsDoNotOverrideApplicationRules`; Python `test_instruction_like_text_in_a_source_is_stored_as_text_only` |
| Arrest, detention, entry, search and seizure kept separate | `testAuthorityCategoriesRemainSeparate`, `testOffenceDoesNotProduceArrestOrSearchPower` |
| Rights and cautions available without a situation or AI | `testRightsAndCautionsAccessibleWithoutScenarioOrAI`, `testCoreWorkflowsWorkWhenLocalAIUnavailable` |
| Missing approved cautions identified | `testMissingApprovedCautionsAreExplicitlyIdentified`, `testDraftWordingIsNeverShownAsApproved` |
| Explanation levels leave exact cautions unchanged | `testExplanationLevelsLeaveCautionsAndLegalContentUnchanged` |
| Reading a caution doesn't record understanding, waiver or compliance | `testReadingCautionDoesNotRecordUnderstandingWaiverOrCompliance` |
| Missing case law and unreviewed rules produce limitations | `testMissingCaseLawAndUnreviewedRulesProduceLimitations`; Python `test_guide_cannot_claim_approval_without_review_record`, `test_approval_requires_matching_approved_review_record` |
| Historical incidents don't silently use the latest law | `testHistoricalIncidentsDoNotSilentlyUseLatestLaw`, `testHistoricalPenaltyRulesAreSelectedByDate` |
| Checklists don't complete themselves | `testChecklistsDoNotCompleteThemselves`, `testDeadlineNotCalculatedFromUnreviewedRule` |
| Offence-to-penalty and offence-to-points mapping | `PenaltyTests.testOffenceToPenaltyAndPointsMapping` |
| Surcharge brackets, boundaries, rounding, costs and totals | `testSurchargeBracketsBoundariesAndRounding`, `testTotalArithmeticWhenAllComponentsVerified` |
| Variable fines and historical penalty rules | `testVariableStatutoryFineBracketsAndBoundaries`, `testHistoricalPenaltyRulesAreSelectedByDate` |
| Missing components prevent an unverified total | `testMissingComponentsPreventUnverifiedTotal`; Python `test_built_db_no_missing_penalty_is_zero` |
| Zero points distinguished from unknown points | `testZeroPointsDistinguishedFromUnknownPoints` |
| Administrative penalties distinct from tickets | `testAdministrativePenaltiesAreDistinctFromOffenceTickets`, `testCourtDeterminedOffencesHaveNoTicketTotal` |
| Every amount and point value links to its source | `testEveryDisplayedAmountLinksToItsSource`; Python `test_penalty_amount_rejected_unless_verified_from_installed_text` |
| Tampered or incompatible packages rejected | `PackageTests.testTamperedPackageIsRejected`, `testUntrustedSignerIsRejected`, `testIncompatiblePackagesAreRejected`; Python `test_tampered_package_is_rejected`, `test_wrong_key_is_rejected`, `test_incompatible_schema_is_rejected`, `test_unsafe_paths_are_rejected` |
| Failed updates keep the last usable package | `testFailedUpdatePreservesLastUsablePackage`, `testRollbackRestoresPreviousPackage` |
| Core workflows work without local AI | `testCoreWorkflowsWorkWhenLocalAIUnavailable`, `testProposedFactsDoNotFeedAnalysisUntilConfirmed` |
| Export and re-import preserve provenance and source versions | `testExportReimportPreservesProvenanceAndSourceVersions` |

Penalty amounts in the Swift tests are **fictional test data**. No real Ontario set-fine, surcharge, costs or demerit-point schedule is installed.

## Running

```bash
scripts/check.sh                                   # Python and consistency checks
cd Packages/PoliceHQCore && swift test             # Swift core (macOS)
xcodebuild test -scheme PoliceHQCore -destination "platform=iOS Simulator,name=iPhone 17"   # run inside Packages/PoliceHQCore
```
