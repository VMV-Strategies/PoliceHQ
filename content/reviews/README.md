# Qualified review records

No review records exist. Do not create records on anyone's behalf.

A qualified reviewer records a decision for one exact guide version in a JSON file here:

```json
{
  "records": [
    {
      "record_id": "2027-001",
      "entry_id": "auth-arrest-peace-officer-warrantless",
      "entry_version": "0.1.0",
      "reviewer": "Full name",
      "qualification": "e.g. Lawyer licensed by the Law Society of Ontario, number ...",
      "scope": "e.g. Operational reference for frontline officers of <service>, Ontario, federal criminal law only",
      "decision": "approved",
      "reviewed_on": "YYYY-MM-DD",
      "notes": "Conditions or limitations of the approval"
    }
  ]
}
```

A guide may set `"review_status": "approved"` only when an `approved` record exists for its exact
`entry_version`; the build fails otherwise. Changing a guide requires a new version and a new review.
