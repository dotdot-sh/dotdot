---
name: dot-tool-scan-frontmatter
description: Surveys a directory of dotdot Markdown docs by printing only each file's frontmatter block using bash dot scan:frontmatter, so a whole directory can be sized up for a fraction of the context that reading the bodies would cost. Use it whenever you need to know what already exists in .dot/Features/ or .dot/Decisions/ — duplicate checks before documenting something new, finding related features or decisions to backlink, or deciding which doc is worth opening in full — rather than globbing, listing, or reading the files themselves.
---

## Usage
```sh
bash dot scan:frontmatter --help
```
