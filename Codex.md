# Factorio Mod Guidelines

## Principles

- This is a Factorio 2.0 mod. Keep code compatible with Factorio's Lua 5.2 environment and current API.
- If Factorio behavior is unclear, verify it in official documentation or existing repo patterns instead of guessing.
- Keep changes small, focused, and easy to review. Prefer the smallest correct change over broad refactors.
- Stay save-compatible. When persistent state or event handling changes, handle initialization and configuration changes carefully.
- Do not introduce new dependencies or broad architecture changes unless the task truly needs them.
- Use subagents to research information in a structured order. Also look out for player opinions on places like Reddit and Steam to find out what tends to be annoying for players.

## Factorio Rules

- Keep prototype/data logic in `data.lua`, startup settings in `settings.lua`, runtime logic in `control.lua`, and player text in `locale/`.
- Do not mix stage-specific APIs or responsibilities.
- Avoid per-tick work unless it is clearly required.
- Update locale and metadata whenever player-facing text or mod identity changes.
- Keep English localization current. Add other locales only when there is a clear product reason.

## Validation

- Before and after any meaningful change, run the best validation available for the repo.
- If an automated harness exists, use it.
- If no automated harness exists yet, use the strongest practical fallback, typically a manual Factorio smoke test, and say what was manual.
- Final status should always state exactly what was validated and what remains untested.
- Use an iterative review process using subagents, if necessary multiple.

## Review Workflow

- For non-trivial code changes, use a code-review subagent after the first implementation pass and again before finalizing.
- The review should check stage separation, event wiring, nil safety, save compatibility, and accidental regressions.
- If the change touches player-facing UI, settings, alerts, messages, or any other visible flow, add a UX review subagent and have it check clarity, defaults, text length, and Factorio-native feel.

## Agent Workflow

- The root agent should act as the manager and architect of the task, guided by the human prompt.
- The root agent should break the work into concrete subtasks, delegate them, integrate the results, and drive the task to a finished state without making the user coordinate the team manually.
- Prefer `gpt-5.4-mini` for normal subagent work such as focused code review, targeted exploration, narrow implementation tasks, and localized validation.
- Prefer `gpt-5.4` for complex subtasks that require deeper reasoning, larger cross-cutting changes, difficult debugging, or ambiguous technical decisions.
- Use subagents deliberately and keep their ownership clear so they can work in parallel without undoing each other.

## Repo Reality

- Treat this repository as a starter workspace: do not assume CI, tests, or extra tooling exist until they are added.
- Prefer solutions that stay easy to merge and easy to extend later.

## Git Workflow

- Agents should handle the full git workflow themselves when the task reaches a coherent stopping point or when the user asks for it.
- This includes inspecting status and diffs, creating branches when useful, committing finished work, merging completed branches, pushing completed work to the configured remote when appropriate, and keeping the worktree tidy.
- Use clear commit messages that describe the user-visible or behavior-level change, preferably in imperative mood.
- Before every commit, review the staged diff and make sure temporary test files, local Factorio data, logs, and generated artifacts are not included unless explicitly intended.
- Prefer non-interactive git commands. If branching, merging, or pushing is needed, do it directly instead of asking the user to finish the git steps manually.
- Unless the user says otherwise, agents should treat git work as end-to-end ownership and should not stop at a local commit if a normal push is the next obvious completion step.
- Do not rewrite published history, force-push, or discard user changes unless the user explicitly asks for that.

## Autonomous Validation

- When gameplay, balancing, pathing, UI, or other in-game effects are changed, try to add or extend a machine-readable way to validate the behavior whenever practical.
- Prefer deterministic smoke tests, scripted scenario checks, admin/debug commands, script-output assertions, or other reviewable harnesses that an agent can run without needing a human to watch the game manually.
- When a fully automated check is not realistic yet, leave the code in a better state for future autonomous validation by adding small debug hooks, reproducible setup commands, or structured logging that can be used in later tests.
- Ask for human review only when the intended in-game behavior remains ambiguous or cannot reasonably be verified through available automated or semi-automated checks.

## Assets

- Assets need to be either completely generated by yourself or found online and be verified to be absolutely free to use and royalty-free, without infringing copyrights or similar rights.
