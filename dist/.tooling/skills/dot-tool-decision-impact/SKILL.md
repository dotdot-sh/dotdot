---
name: dot-tool-decision-impact
description: Finds what a project decision touches, using bash dot decision:impact — which documented features cite it, which features and decisions talk about the things it constrains, which decisions point back at it, and whether every reference between decisions still resolves to a real file. Reach for it before writing a new decision, before relying on or changing an existing one, and whenever you need to know what would break if a decision moved: "what does decision 004 affect", "which features depend on this", "is anything superseding this", "did that rename break the decision links". Use it instead of grepping .dot/Decisions/ or .dot/Features/ by hand.
---

## Usage
```sh
bash dot decision:impact --help
```
