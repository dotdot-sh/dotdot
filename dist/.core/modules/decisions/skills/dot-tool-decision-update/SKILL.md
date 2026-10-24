---
name: dot-tool-decision-update
description: Changes a project decision's status in .dot/Decisions/ and refreshes its "modified" timestamp in one step, using bash dot decisions:update. Use it whenever a decision's standing changes — accepting a draft, rejecting or deprecating one, or retiring one that a newer decision replaces: "we're going with 007 instead", "that decision is dead now", "mark this one accepted", "deprecate 004", "005 supersedes it". Reach for it rather than editing the frontmatter by hand, which reliably updates the status and forgets the timestamp; it also builds the "superseded by" link from a reference it checks, so a retired decision can never point at one that does not exist.
metadata:
  internal: true
---

## Usage
```sh
bash dot decisions:update --help
```
