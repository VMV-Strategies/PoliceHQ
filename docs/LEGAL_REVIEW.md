# Legal-content review

Importing legislation does not create reviewed guidance. Police HQ keeps five states distinct:

| State | Meaning | How it is set |
|---|---|---|
| Imported source | The file was ingested. | Automatically, for every source. |
| Extraction verified | A person compared the structured text with the original. | Registry override with reviewer and date. |
| Editorial interpretation drafted | A guide (authority, right, caution, offence, checklist) was written. | `review_status: "interpretation-drafted"` (every guide in this package). |
| Qualified legal review recorded | A qualified reviewer recorded a decision for an exact guide version. | A record in `content/reviews/*.json`. |
| Approved for a defined operational scope | The guide may be presented as operational guidance within the recorded scope. | `review_status: "approved"` plus a matching `approved` record. The build fails without one. |

**Current state:** no review records exist. Every guide is a draft, and the app labels every guide *Draft — review required*. The `gap-legal-review` gap appears wherever guides are used.

## What reviewers check

1. **Citations:** every citation points to the right provision, in force for the intended scope.
2. **Quotes:** every quoted threshold is complete for its purpose. Quotes are verbatim by construction; the build checks that.
3. **Conditions, limits and not-authority-for lists:** these are accurate and complete for the scope.
4. **Summaries:** the drafted summaries (very simple, plain, detailed) don't change the legal test.
5. **Missing law:** the case law, regulations and policies the guide depends on are installed, or the gap is shown.
6. **Checklist items:** triggers and applicability are correct.
7. **Penalty components:** each is mapped to the right offence, with effective dates and date triggers.

## Recording a review

Create `content/reviews/<id>.json` (see `content/reviews/README.md`). It must have reviewer, qualification, scope, decision and date, for one `entry_version`. Then change the guide's `review_status` to `approved`. Any edit to a guide requires a new `version`, which invalidates the earlier approval.

The tools never generate reviewers, approval dates or validation.

## Adding approved caution wording

1. Obtain the service-approved wording, its version and the approving organization.
2. In `content/guides/cautions.json`, set `approved_wording` (exact text), `approving_organization` and `version`, then record an approved review for that version.
3. Rebuild and sign the package.

Until all of those exist, the app shows **Approved wording not installed.**, identifies what's missing, and never substitutes generated or paraphrased text. Unverified translations must not be added as approved wording.

## Adding deadline rules

`DeadlineCalculator` calculates a deadline only when a rule is marked `validated: true` and its guide is approved. Record the trigger, duration and exceptions in the guide's `deadline_rule`, and have them reviewed.
