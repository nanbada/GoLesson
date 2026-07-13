# 2026-07-10 AGENTS Optimization Handoff

## Goal

- Optimize repository guidance for GPT-5.6 Sol/Terra/Luna orchestration, token discipline, and verified task routing.
- Allow GPT-5.5 only when it adds specific value.

## Decisions

- Sol remains the root orchestrator and deepest/final-quality model.
- Terra is the bounded complex-work all-rounder, not the deepest model.
- Luna handles clear repeatable work and deterministic checks.
- GPT-5.5 is an exception for 5.6 unavailability, pinned compatibility, or an independent previous-generation second opinion.
- Do not spawn every role. Delegate only independent or context-noisy work; default to root plus two workers and depth one.
- `AGENTS.md` routing is intent, not a guarantee that the runtime selected a model. Actual pinning requires custom agent configuration when the runtime supports it.

## Changed

- Updated `AGENTS.md`:
  - corrected the product description to time-block learning with rotating 1:1 coaching;
  - added model-aware orchestration and high-risk final-review ownership;
  - added context/token discipline and task-specific document routing;
  - reduced default memory/SSOT reads;
  - removed time-sensitive go-live duplication and the redundant repository map;
  - replaced drifting RPC names with SSOT/migration lookup;
  - added scoped verification commands.
- Updated Claude entrypoints so the next Claude session sees all 2026-07-10 local product/UI/auth changes and their unverified/deployment boundaries:
  - `CLAUDE.md`
  - `aidd_docs/plans/claude-handoff-prompt.md`
  - `aidd_docs/plans/session-kickoff-prompt.md`
- Added the global `openaiDeveloperDocs` MCP registration because the OpenAI docs skill required it after the Codex manual helper failed integrity-header validation. A Codex restart is needed before that MCP becomes callable in a new session.

## Evidence

- Official Codex model docs identify Sol as flagship/deepest, Terra as balanced, Luna as fast/affordable, and recommend the lowest reasoning effort that meets the task.
- Official subagent docs state that subagents cost more tokens, recommend read-heavy parallel work, warn about write conflicts, and document model/reasoning overrides in custom agent files.
- `AGENTS.md` is 8,949 bytes, below the 32 KiB default project instruction limit.
- `git diff --check` passed.

## Unfinished

- No `.codex/agents/*.toml` or project `.codex/config.toml` was added because the user requested `AGENTS.md` optimization only. Add those later only if per-agent model pinning must be enforced.
- The current global `~/.codex/config.toml` still selects `gpt-5.6-sol` with `model_reasoning_effort = "high"`. `AGENTS.md` cannot lower that setting; change it separately only if the user wants actual default-token savings.
- Existing unrelated working-tree changes from the prior product/login task remain untouched.
- No commit or push was performed.
