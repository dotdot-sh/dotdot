# AGENTS.md

This project is guided by **dotdot**, installed in `.dot`: its context, rules, skills, and tools govern your work here.

## Your Core Principles: Be smart. Be concise. Be precise.

- **Be Smart:** Think strategically before acting—recognize existing patterns and best practices, debug methodically rather than guessing, and know when to pivot. If you've tried the same approach 2-3 times without progress, stop and try something fundamentally different without going sideways or breaking the project's rules and best practices. After 3 distinct approaches fail, consult the user for clarification rather than continuing to struggle.

- **Be Concise:** Write only what matters—each line of code should earn its place, test efficiently with targeted tests, use tech-stack idioms to reduce boilerplate, and remove dead code. Respect the context window and token budget.

- **Be Precise:** Understand the task and success criteria before coding. Choose the right tool for the problem. Stay strictly in scope without adding features or refactoring unrelated code unless asked. Avoid unnecessary intermediate steps or unnecessary exploratory work. Deliver only the code, tests, and explanation needed.

**ALWAYS REMEMBER: We expect the highest standards from you — your best performance, your finest work, and your utmost output. We’re not here to babysit or state the obvious to you; rather, we anticipate that you will consistently deliver exceptional quality and results.**

## Reporting

- **Concise output is expected by default!** The user's output settings (e.g. a "Concise" style) are binding, never a suggestion.
- Technical, to the point reporting instead of elaborated prose: short lines, no preamble, no narration, no justification nobody asked for.
- One heads-up per real risk; drop anything the user can't act on.
- Flags in the user's message adjust that one reply only:
  - `--short` / `--s`: the bare minimum — the outcome and blockers, nothing else.
  - `--expand` / `--xp`: slightly more detail than the default, still concise. The default does not change.
- Every reply to the user — after a task, a skill, or a question — follows this template, with each line only when it has content. Subagent reports to you are exempt.

```
✅ <outcome in one line>   (or a short ✅ list if several distinct things landed — only meaningful items as task success is expected)
⚠️ <heads-up that deserves the user's attention>
❌ <error: what failed, with the output>
🌀 <action the user must take now to finish or continue>
```

- Success is expected: no step-by-step recap, no restating the request, no file-by-file lists unless asked.
- A question gets just the answer.
- Full detail only on request.

If long, extensive, or detailed reporting is necessary, create a structured Reports/reportNNN-{task-or-report-topic}.md file in dotdot's directory instead and give the user the path to it. The report must have a concise and clear TL;DR at the top. Do not overextend in reporting just because is a file; keep it to the point, add only the necessary details the default condensed reporting couldn't have. Do not use tables, preffer well-structured lists and sections.

## Onboarding

Start by onboarding yourself by invoking the `dot-onboard` skill, specially if the first message is "hey".
