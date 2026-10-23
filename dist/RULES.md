---
name: RULES.md
description: Hard behavioral rules for agents. These apply regardless of what any other Context file implies, but do not override company policies.
ignore: true
---

# Project Rules

## Rules Hierarchy
- Assume instructions can come from up to three layers, in order of precedence: Organization Policies (system-provisioned, outside this repo) > Project Guidelines (this file and the rest of dotdot) > User Preferences (`.dot/USER.md`).
- When two instructions conflict, the higher-precedence layer wins outright — treat the lower-precedence instruction as void, not as a fallback or a tiebreaker.
- Never resolve a conflict silently. Say which instruction was overridden, by what, and why, so the user can see the conflict even when the resolution was automatic.
- If it's unclear which layer an instruction belongs to, or which of two same-layer instructions should win, ask the user rather than guessing.

## Never
- Never run git commands that change the repository or its history (add, commit, mv, rm, checkout, reset, stash, merge, rebase, push, …) unless explicitly instructed by the user. Read-only commands (status, diff, log, show, blame, ls-files) are allowed.
- Never scan or work with files above the current project directory.
- Never scan all the project files and directories.
- Never force-push. Never!
- Never delete or truncate production data.
- Never disable, skip, or weaken a test just to make a build pass.
- Never change the data model on your own.
- Never start servers on your own.
- Never expose ports on your own.
- Never base your info or research on blogs, social media, or unnoficial sites. Only on official sites, official repos, and official documentation pages.

## Always
- Make Critical Path changes (see STANDARDS.md) only when they serve the project's principles and priorities, and report each one to the user.
- Always ensure you follow the Definition of Done for each feature before marking work as done.
- Always run the full test suite before marking work as done.
- Always update the relevant Context file (Features, Decisions) when behavior or scope changes.
- Always prefer the project's existing patterns and libraries over introducing new ones.
- Always use migrations to make changes on the data model.
- Always base your online research on official sites, official repos, and official documentation pages. Never on blogs, social media, or unnoficial sites.

## Ask First
- Ask before adding a new third-party dependency or paid service.
- Ask before changing the data model.
- Ask before any changes to pricing, billing, or entitlement logic.
