# Big Red subscription-backed agent peers

Big Red can host Claude Code and Google Antigravity CLI as full local coding peers for Codex, Pi, or an operator. Codex remains the coordinator and should delegate substantial reviews, implementation work, research, test/debug loops, and independent second attempts to the subscription-backed peers whenever useful.

Provider account authentication remains provider-owned. Nothing here copies provider tokens into GitHub or Glaeda.

## Current provider choice and defaults

Use **Claude Code** for the Claude subscription and **Antigravity CLI** for the Google AI subscription.

The delegated defaults are pinned rather than following a moving latest alias:

```text
Claude Code:     claude-opus-5          effort high
Antigravity CLI: gemini-3.7-flash-high effort high
```

`claude-opus-5` is Anthropic's active Opus 5 model ID. Antigravity exposes `gemini-3.7-flash-high` as the high-effort Gemini 3.7 Flash model. Google moved Google AI Pro/Ultra and individual Code Assist CLI usage from Gemini CLI to Antigravity CLI in June 2026, so do not add a second Gemini CLI consumer login merely for this route.

Upstream references:

- Claude Code setup: https://code.claude.com/docs/en/setup
- Claude Code CLI/headless reference: https://code.claude.com/docs/en/headless
- Claude Code permission modes: https://code.claude.com/docs/en/permission-modes
- Claude Opus 5: https://www.anthropic.com/news/claude-opus-5
- Antigravity CLI install/auth: https://antigravity.google/docs/cli/install/
- Antigravity CLI headless mode: https://antigravity.google/docs/cli/headless/
- Antigravity permissions: https://antigravity.google/docs/cli/permissions/
- Gemini 3.7 Flash: https://ai.google.dev/gemini-api/docs/models/gemini-3.7-flash

## Install without authenticating

From a reviewed checkout of this repository on Big Red:

```bash
scripts/install-big-red-agent-peers --plan
scripts/install-big-red-agent-peers
scripts/install-big-red-agent-peers --verify-only
```

The installer uses the official native installers:

- Claude Code stable channel, expected launcher `~/.local/bin/claude`;
- Antigravity CLI, expected launcher `~/.local/bin/agy`, installed with an explicit `--dir ~/.local/bin` while the upstream installer's setup handoff runs under a disposable HOME so it cannot rewrite the operator's shell profiles;
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

Do not add `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `GOOGLE_API_KEY`, or `OPENAI_API_KEY` merely to power these subscription-backed peers. The wrapper explicitly unsets inherited model API/provider variables before delegated runs so a caller's environment cannot silently switch from the intended subscription account onto API billing.

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

All three are **full-capability agent runs**. `review`, `work`, and `run` differ only in the instruction prefix. A review agent may inspect files, run commands/tests, browse, use MCP/plugins/skills, and edit a concrete fix when useful. The point is to consume the available peer subscriptions as real subordinate coding agents, not as read-only text generators.

### Claude

Delegated Claude calls intentionally do **not** use `--safe-mode`, `--bare`, a tool whitelist, or `dontAsk`.

The default invocation includes:

```text
--model claude-opus-5
--effort high
--dangerously-skip-permissions
--output-format json
```

This loads the normal Claude Code configuration and gives the delegated run its complete local tool surface without permission prompts. `BIG_RED_CLAUDE_MODEL` and `BIG_RED_CLAUDE_EFFORT` remain explicit overrides, but orchestration should normally leave them at Opus 5/high.

### Antigravity

Delegated Antigravity calls intentionally do **not** use `--sandbox`, a disposable review copy, or restrictive permission rules.

The default invocation includes:

```text
--model gemini-3.7-flash-high
--effort high
--dangerously-skip-permissions
--output-format json
--print-timeout 60m
```

Normal Antigravity settings/plugins/skills/MCP configuration under the user's ordinary HOME remain available. `BIG_RED_ANTIGRAVITY_MODEL` and `BIG_RED_ANTIGRAVITY_EFFORT` remain explicit overrides, but orchestration should normally leave them at Gemini 3.7 Flash/high.

Both providers have an outer default timeout of 90 minutes, configurable through `BIG_RED_AGENT_TIMEOUT`. After TERM, `BIG_RED_AGENT_KILL_AFTER` (default `30s`) bounds the grace period before KILL. A forced KILL returns exit 137 and is retained in the usage receipt; ordinary timeout termination returns 124. This bounds the direct provider process; `--foreground` does not promise descendant cleanup.

Run `bash tests/test-big-red-agent-peer.sh` for peer checks, including all three providers ignoring TERM, or `bash tests/test-big-red-timeout-reliability.sh` for that focused regression.

## Usage accounting

Every delegated `review`, `work`, or `run` stores one content-free local receipt in:

```text
~/.local/state/big-red-agent-peer/usage.jsonl
```

The ledger is owner-only mode `0600`, append-locked for concurrent peer runs, and records only:

- provider, pinned/requested model, effort, and delegation mode;
- start/end and wall duration;
- exit/provider status;
- input, cached input, cache-creation input, output, reasoning/thinking, and total token counters when reported;
- result byte count;
- Claude's provider-reported `total_cost_usd` only as `api_equivalent_estimate_usd`.

It never records the prompt, response, conversation/session ID, repository/path, account identity, or credential. Because these are subscription-backed calls, `billing_class` is `subscription` and `actual_marginal_cost_usd` remains `null`. Claude's cost value is a client-side API-equivalent estimate, not the subscription bill.

Inspect the last seven days with:

```bash
big-red-agent-peer usage
```

or another whole-hour window with:

```bash
big-red-agent-peer usage 24
```

The normalized fields intentionally match the token vocabulary already used by Big Red's Scrapbook/Codex accounting so a later dashboard slice can add peer-labelled hourly totals without redefining token semantics.

## Coordination pattern

The normal pattern should favor breadth and parallelism. Codex should hand off lots of useful independent work rather than reserving the peers for exceptional cases. For example:

```text
Codex scopes a change
├─ Claude Opus 5/high investigates, tests, and reviews
├─ Gemini 3.7 Flash/high independently investigates, tests, and reviews
├─ one or both implement concrete fixes or alternate attempts
└─ Codex compares the evidence, runs/finalizes the authoritative project gate, and integrates
```

Parallel peer calls are expected. Their usage receipts are append-locked so concurrent delegations remain countable.

The subscriptions are optional compute/intelligence sources: if Claude or Google quota/auth is unavailable, Glaeda and ordinary Big Red execution continue. The local usage ledger is visibility, not a budget cap; the explicit goal is to make productive use of the available subscription quota.

## First smoke after login

Start in an ordinary task worktree:

```bash
cd ~/Projects/glaeda
big-red-agent-peer review claude -- \
  'Inspect the repository, run useful checks, and report anything suspicious.'
big-red-agent-peer review antigravity -- \
  'Independently inspect the repository, run useful checks, and report anything suspicious.'
big-red-agent-peer usage
```

Then give each provider real bounded issues on task-owned worktrees and let them use the full local tool surface. Inspect resulting diffs and verification evidence afterward.

## Operator boundary

Installing the CLIs and establishing provider OAuth sessions are Big Red machine/account mutations. Execute those after review under the operator's action boundary. Browser OAuth, passkeys, one-time codes, CAPTCHA, and recovery remain human-confirmed.

The full unattended permission flags are intentional for these delegated coding sessions. They give the peer agents broad local development capability on this owned workstation. Keep important source work in Git/task worktrees so changes remain inspectable and recoverable.
