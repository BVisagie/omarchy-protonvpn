<!-- shopfloor:start -->
## Workflow: Untitled

These rules come from a shopfloor recipe and apply to work in T3 Code, which tells you in your instructions when you are running in it. In any other session, ignore them. To change them, change the recipe and install it again.

### Plan

- Models that plan, preferred first: Opus 5.5 (`claudeAgent` · `claude-opus-5-5` · `effort: high`).
- If this thread runs a model that is not on that list, say so once and plan all the same.
- When asked to plan, research, diagnose or design, change no files. End with a written plan, then stop and wait for the user.
- End every plan by naming the build model: `Build model: Opus 5.5 with effort high. Switch to it if this thread runs a model or a setting that is not listed under Build, then say "execute the plan".`

### Build

- Models that build, preferred first: Opus 5.5 (`claudeAgent` · `claude-opus-5-5` · `effort: high`).
- "Execute the plan", or close wording, starts the `shopfloor-build` skill.

### Review

- Before you open a pull request or push to a default branch, run the `shopfloor-review` skill. Only the user can skip it, in their current message.

### Advisor

- The advisor is Fable 5.2 (`claudeAgent` · `claude-fable-5-2` · `effort: high`). It gives a second opinion. It reads and answers, and never edits.
- Ask it with the `shopfloor-advise` skill:
  - before you show a plan to the user, once for each plan
  - when the same check or fix has failed twice, before a third try
  - when a reviewer still holds a finding after it has read your reasons, before you ask the user
  - when the user asks for it
- While you plan, your tools may be read-only and refuse to start it. Then write in the plan that the advisor has not read it. The build asks it first.
- Ask at most 3 times in one task. A task is one plan and its build.
- Its answer is advice. Weigh it and decide yourself. Tell the user what it said, and say so when you did not follow it.

### Limits

- Run at most one subagent at a time. Wait for it to finish before you start another.
- Tell every subagent that it may not start subagents of its own.

### Skills

- Use the `ponytail` skill on every coding task.
- Use the `unslop` skill when a change touches UI.
- Use the `modern-web-guidance` skill when a change touches HTML, CSS or browser JavaScript, with DISABLE_TELEMETRY=1 before every command that runs its tool.
- If a skill named here is not installed, say so once and carry on without it.
<!-- shopfloor:end -->
