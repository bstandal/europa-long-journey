# Narration finalist selections

This directory remains empty of approved decisions until the editor-in-chief
has listened to all six complete candidate readings and explicitly selected two
finalists for the uninterrupted stress test.

An approved record is created only after that decision. The production parser
requires exactly these fields:

```json
{
  "schemaVersion": 1,
  "status": "APPROVED_BY_EDITOR_IN_CHIEF",
  "decisionType": "NARRATION_STRESS_FINALISTS",
  "approvedBy": "editor-in-chief",
  "decidedAt": "RFC-3339 timestamp with timezone",
  "decisionReference": "versioned reference to the explicit decision",
  "candidateSetReceiptSHA256": "SHA-256 of the complete six-candidate receipt bytes",
  "candidateSetReceiptBytes": "exact byte count of the complete six-candidate receipt",
  "selectedCandidateIDs": ["exactly two distinct anonymous candidate IDs"]
}
```

The record's own byte count and SHA-256 enter the stress-test receipt. Changing
the selection record, candidate-set receipt, pipeline, configuration, lockfile,
voice instruction or FFmpeg binary invalidates production.

`fixtures/editor-selection.not-approved.json` documents a deliberately rejected
state. It is not an editorial decision and cannot unlock stress generation.
