# Big Red Muse peer

Big Red can use OpenCode with OpenCode Zen's `Muse Spark 1.3 Contributor Free` endpoint as a full local coding peer. This route is deliberately separate from the subscription-backed Claude/Antigravity wrapper because the billing/data contract is different and the free endpoint may disappear.

## Current contract

- OpenCode model: `opencode/muse-spark-1.3-contributor-free`
- Billing class: Contributor Free while OpenCode lists the model as free
- Data contract: prompts and completions may be used to train future Meta models
- Agent: OpenCode `build`
- Permissions: unattended/full local tool use (`--auto`, with compatibility fallback to the older `--dangerously-skip-permissions` spelling)
- Run output: OpenCode JSON events are captured privately; only assistant text is returned to the caller
- Usage accounting: content-free receipts at `~/.local/state/big-red-muse-peer/usage.jsonl`

The launcher pins the explicit `opencode/...` model route so configured Anthropic, Google, or OpenAI credentials do not silently become the model backend.

## Install

From the reviewed `compute-node-bootstrap` checkout on Big Red:

```bash
scripts/install-big-red-muse-peer --plan
scripts/install-big-red-muse-peer
scripts/install-big-red-muse-peer --verify-only
```

The installer downloads OpenCode's official install script, prints its SHA-256 receipt, lets it install OpenCode in its supported `~/.opencode/bin` location, and links the verified executable into `~/.local/bin` without asking the upstream installer to edit shell startup files. It also installs the reviewed `big-red-muse-peer` launcher and verifies the CLI capabilities required by the wrapper. It never reads or writes OpenCode Zen credentials.

The separate link keeps the stable Big Red launcher contract while allowing the upstream installer to manage OpenCode in its current default location.

## Authenticate OpenCode Zen

Authentication remains an explicit operator-owned step:

```bash
big-red-muse-peer auth
```

This invokes `opencode auth login --provider opencode`. OpenCode stores provider credentials in its user-local credential store. Keep API keys and credential-store contents out of GitHub and workspace prose.

The OpenCode Zen account/API key can be the same account used on another machine; Big Red still needs its own local OpenCode credential entry.

## Delegate

Run from any owner Git worktree:

```bash
big-red-muse-peer review -- 'Independently inspect this change, run useful checks, and report or fix concrete issues.'
big-red-muse-peer work -- 'Implement the remaining issue and verify it.'
big-red-muse-peer run -- 'Take this task to a concrete result.'
big-red-muse-peer usage
```

`review`, `work`, and `run` are instruction roles. They all use OpenCode's full build agent and unattended permissions.

## Accounting

Each completed invocation writes one mode-0600, content-free receipt containing provider/model, mode, timing/status, input/output/reasoning tokens, cache reads/writes, OpenCode-reported cost, and result byte count. Prompts, responses, session IDs, repository paths, credentials, and tool payloads are excluded.

OpenCode's JSON event stream reports token counters on `step_finish` events. The wrapper sums every observed step so long tool-using runs are represented by their full token traffic. `big-red-muse-peer usage` summarizes the previous seven days by default.

This ledger stays separate from `big-red-agent-peer/usage.jsonl` so existing subscription summaries keep their billing semantics. Scrapbook can ingest both ledgers under provider-labelled accounting later.

## Failure boundary

OpenCode Zen auth/quota/model removal never blocks ordinary Big Red, Glaeda, Claude, Antigravity, or Codex work. If the free Muse model disappears, the pinned model should fail visibly instead of silently selecting a paid fallback.
