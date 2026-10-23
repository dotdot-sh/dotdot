---
name: <short kebab-case feature slug>
description: <one-line summary — this is what bash dot scan:frontmatter matches on for duplicate/relation checks>
---

# {Feature Name}

> Every section below is filled or written as exactly `None`. Never explain an empty section with prose.

## Description
What the feature is and why it exists, in plain language.

## Specification
BDD-like language. A `**Scenario (Golden):**` for each thing the feature must do, with its `**Scenario (Edge):**` scenarios (honest malfunctions and misuse — what the user gets wrong, what the outside world returns) and `**Scenario (Adversarial):**` scenarios (malicious intent — what an attacker tries, what must be refused) directly beneath it. Behavioural cases only. A Golden with no Edges beneath it is unfinished, and so is one that untrusted input can reach with no Adversarials.

## Constraining Rules
Filenames only, one per line, of what applies to this feature (RULES.md, STANDARDS.md, DESIGN.md, company policies present in the system). No descriptions. `None` if nothing applies.

## Related Project Decisions
Filenames only, one per line, of existing decisions (.dot/Decisions/) that shape how this feature must work. No descriptions. `None` if nothing applies.

## Feature-Specific Decisions
Consequential choices scoped to this feature alone — an approach or tradeoff that constrains implementation — not general enough to be a standalone Decision. Never restate what the Specification scenarios already define: branches, error paths, and validation rules are not decisions. `None` if there are none.

## Data Model
What it needs and touches on the database. Tables, columns, relations. `None` if it touches none.

## File Map
`None` until implemented. Then three lists:
- **Owns:** directories the feature introduced, code and tests. No single files unless outside of owning directories.
- **Touches:** `filepath@method` in other features' code this feature changed.
- **Used by:** `filepath@method` outside Owns that use this feature's code.

## Technicalities
Technical details, dependencies, code examples, usage, etc, to technically understand or use this feature across the project. Only relevant details or caveats, the code is normally its own documentation. `None` if there are none.

## Related Features
Filenames only, one per line, of other features this one overlaps, depends on, or is commonly discussed alongside. No descriptions. `None` if there are none.

## Implementation Plan
Plan drafted by the coding agent. `None` until drafted.

### Definition of Done (DoD)
- [ ] Run full test suite and confirmed nothing fails
- [ ] Update or document Related Decisions
- [ ] Update DATAMODEL.md
- [ ] Update SCHEMA.md
- [ ] Document Related Features in all relations
- [ ] Update File Map here and Used by in the features whose code this one uses.
