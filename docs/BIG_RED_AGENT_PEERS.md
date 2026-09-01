# Big Red subscription-backed agent peers

Big Red can host Claude Code and Google Antigravity CLI as full local coding peers for Codex, Pi, or an operator. The intended use is simple: Codex remains the coordinator, but it can hand substantial reviews, implementation work, research, and test/debug loops to the other subscription-backed agents.

Provider account authentication remains provider-owned. Nothing here copies provider tokens into GitHub or Glaeda.

## Current provider choice

Use **Claude Code** for the Claude subscription and **Antigravity CLI** for the Google AI subscription.

Google moved Google AI Pro/Ultra and individual Code Assist CLI usage from Gemini CLI to Antigravity CLI in June 2026. Do not add a second Gemini CLI consumer login merely for this route.

Upstream references:

- Claude Code setup: https://code.claude.com/docs/en/setup
- Claude Code CLI/headless reference: https://code.claude.com/docs/en/headless
- Claude Code permission modes: https://code.claude.com/docs/en/permission-modes
- Antigravity CLI install/auth: https://antigravity.google/docs/cli/install/
- Antigravity CLI headless mode: https://antigravity.google/docs/cli/headless/
- Antigravity permissions: https://antigravity.google/docs/cli/permissions/

## Install without authenticating

From a reviewed checkout of this repository on Big Red:

```bash
scripts/install-big-red-agent-peers --plan
scripts/install-big-red-agent-peers
scripts/install-big-red-agent-peers --verify-only
```

The installer uses the official native installers:

- Claude Code stable channel, expected launcher `~/.local/bin/claude`;
- Antigravity CLI, expected launcher `~/.local/bin/agy`, with `--skip-path --skip-aliases` so its installer does not rewrite shell profiles;
- reviewed peer wrapper copied byte-for-byte to `~/.local/bin/big-red-agent-peer`.

The installer downloads each upstream installer to an owner cache first and reports its observed SHA-256. The upstream installer endpoints are mutable, so those digests are observations rather than repository pins.

The install script never starts account authentication and never reads provider credential stores.

## Authenticate

```bash
big-red-agent-peer auth claude
big-red-agent-peer auth antigravity
```

Claude Code uses `claude auth login`. Sign in with the subscription account. On a remote terminal, follow Claude's browser/code flow when appropriate.

Antigravity uses its interactive `agy` login. Over SSH it can print a provider authorization URL; open it locally, complete Google sign-in, and return the provider code to the Big Red terminal.

Do not add `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `GOOGLE_API_KEY`, or `OPENAI_API_KEY` merely to power these subscription-backed peers. The wrapper explicitly unsets inherited model API/provider variables before delegated runs so a caller's environment cannot silently switch the run from the intended subscription account onto API billing.

Other normal user capabilities remain available: ordinary provider settings, project configuration, hooks, plugins, skills, MCP servers, PATH/toolchains, GitHub credentials, SSH-agent state, and other user environment needed by coding tools.

## Full delegated runs

The wrapper exposes three run labels:

```bash
big-red-agent-peer review claude -- 'Review the current change deeply.'
big-red-agent-peer review antigravity -- 'Review the current change deeply.'

big-red-agent-peer work claude -- 'Implement the remaining issue and verify it.'
big-red-agent-peer work antigravity -- 'Implement the remaining issue and verify it.'

big-red-agent-peer run claude -- 'Investigate this however you think is useful.'
big-red-agent-peer run antigravity -- 'Investigate this however you think is useful.'
```

All three are **full-capability agent runs**. `review`, `work`, and `run` differ only in the instruction prefix. A review agent may inspect files, run commands/tests, browse, use MCP/plugins/skills, and edit a concrete fix when useful. The point is to use the subscriptions as real subordinate coding agents, not as read-only text generators.

### Claude

Delegated Claude calls intentionally do **not** use `--safe-mode`, `--bare`, a tool whitelist, or `dontAsk`.

They run with:

```text
--dangerously-skip-permissions
--effort max
--output-format json
```

This lets the normal Claude Code configuration load and gives the delegated run its complete local tool surface without permission prompts. Set `BIG_RED_CLAUDE_MODEL` to override the configured/default model and `BIG_RED_CLAUDE_EFFORT` to override the default `max` effort for a particular orchestration context.

### Antigravity

Delegated Antigravity calls intentionally do **not** use `--sandbox`, a disposable review copy, or restrictive permission rules.

They run with:

```text
--dangerously-skip-permissions
--effort high
--output-format json
--print-timeout 60m
```

Normal Antigravity settings/plugins/skills/MCP configuration under the user's ordinary HOME remain available. Set `BIG_RED_ANTIGRAVITY_MODEL` or `BIG_RED_ANTIGRAVITY_EFFORT` when Codex wants a different model/effort.

Both providers also have an outer default timeout of 90 minutes, configurable through `BIG_RED_AGENT_TIMEOUT`.

## Coordination pattern

The normal pattern should be breadth rather than ceremony. For example:

```text
Codex implements or scopes a change
-> Claude reviews/tests it at full capability
-> Antigravity independently reviews/tests it
-> Codex compares their findings
-> one peer fixes a concrete issue if useful
-> Codex runs/finalizes the authoritative project gate
-> GitHub review/merge proceeds normally
```

Or Codex can assign independent implementation attempts and compare them. The peers are optional sources of compute/intelligence; their quota/auth availability never becomes a dependency for Glaeda or Big Red itself.

## First smoke after login

Start in an ordinary task worktree:

```bash
cd ~/Projects/glaeda
big-red-agent-peer review claude -- \
  'Inspect the repository, run a useful lightweight check, and report anything suspicious.'
big-red-agent-peer review antigravity -- \
  'Independently inspect the repository, run a useful lightweight check, and report anything suspicious.'
```

Then give each provider a real bounded issue on a task-owned worktree. Let it run commands/tests and inspect the resulting Git diff/receipts afterward.

## Operator boundary

Installing the CLIs and establishing provider OAuth sessions are Big Red machine/account mutations. Execute those after review under the operator's action boundary. Browser OAuth, passkeys, one-time codes, CAPTCHA, and recovery remain human-confirmed.

The full unattended permission flags are intentional for these delegated coding sessions. They give the peer agents the same kind of broad local development capability expected from Codex on this owned workstation. Keep important source work in Git/task worktrees so changes remain inspectable and recoverable.
