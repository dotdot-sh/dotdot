---
name: NOMENCLATURE.md
description: The terms and naming rules of this project, in docs, talks, and code. Use it whenever you name, write about, or discuss anything in this project (classes, methods, variables, files, docs, and conversations).
ignore: true
---

# Nomenclature

One concept, one term, everywhere: in the docs, the UI, dotdot, the code, and our conversations. When choosing a name, weigh in this order: clarity, shortness, simplicity, fluent readability, the stack's conventions, then industry conventions.

## Registers

A name depends on who reads it.

**Product and technical terms.** Product terms are the words users read in the UI and the docs, and the words we use when we talk. Technical terms are what the code calls the same concept. Both are the same word unless a term below says otherwise.

## Terms

Each term states what it means in this project, followed by the words not to use for it.

_Which domain concepts does this project have, and which words must never stand in for them?_

Format:

```
#### {Term}
{What it means in this project, in one or two sentences.}
**Wrong:** {words not to use for it}.
```

## Naming Rules

The rules describe patterns, not specific methods. Examples show a pattern and may go stale as the code changes; the rule does not.

### Methods

- Methods are a single verb or noun when that is clear.
- Getters are plain nouns, without `get`.
- Methods with a verb and a noun say what they do and to what (`sendInvoice`, `archivePosts`).
- Booleans start with `is`, `has`, `can`, or `should`.

Generic words never stand alone in any name: data, info, item, manager, helper, util, handler, process.

### Functions and Variables

Variables are full-word nouns, plural for lists, never abbreviated: `invoice` and `lineItems`, never `inv` or `arr`.

### Constants

Constants are SCREAMING_SNAKE_CASE.

## Exceptions to the Rules

A name may break these rules for one of three reasons only:

- The language or framework requires it.
- An official external term applies: an API's own field or limit name.
- It keeps an alias developers of the stack expect.
