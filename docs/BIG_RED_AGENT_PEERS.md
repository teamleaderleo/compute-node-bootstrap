# Big Red subscription-backed agent peers

Big Red can host Claude Code and Google Antigravity CLI as user-scoped peer agents for Codex, Pi,
or an operator. Provider accounts stay provider-owned: this setup installs the CLIs and gives them a
bounded invocation wrapper, but authentication remains an explicit interactive step and no credential
value is copied into this repository.

## Current provider choice

Use **Claude Code** for the Claude subscription and **Antigravity CLI** for the Google AI
subscription.

Google moved Google AI Pro/Ultra and individual Code Assist CLI usage from Gemini CLI to
Antigravity CLI in June 2026. Do not add a second Gemini CLI login just for the consumer subscription.

Upstream references:

- Claude Code setup: https://code.claude.com/docs/en/setup
- Claude Code CLI/headless reference: https://code.claude.com/docs/en/headless
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

- Claude Code, stable channel, expected launcher `~/.local/bin/claude`;
- Antigravity CLI, expected launcher `~/.local/bin/agy`, with `--skip-path --skip-aliases` so its
  installer does not rewrite the shell profile.

The installer downloads each upstream installer into an owner cache directory before executing it
and reports that installer file's observed SHA-256 as receipt evidence. The upstream installers are
mutable provider endpoints, so that digest is observation, not a repository pin.

The install script never launches an account login and never reads a provider credential store.

## Authenticate each dedicated peer session

Run these from the logged-in Big Red desktop or an SSH terminal:

```bash
scripts/big-red-agent-peer auth claude
scripts/big-red-agent-peer auth antigravity
```

Claude Code uses `claude auth login`. Sign in with the Claude subscription account. On a remote
terminal, follow Claude's browser/code flow if the callback cannot reach Big Red.

Antigravity uses its interactive `agy` login. Over SSH it prints a provider authorization URL; open
that URL locally, complete Google sign-in, and paste the returned alphanumeric code into the Big Red
terminal.

Do not add `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `GOOGLE_API_KEY`, or provider tokens to shell
profiles for this subscription-backed route. The peer wrapper starts providers from a clean
environment and intentionally drops ambient API keys, GitHub tokens, SSH-agent access, cloud
credentials, and arbitrary caller variables.

The wrapper also gives each provider purpose-specific state:

- Claude: `~/.local/state/big-red-agent-peer/claude` through `CLAUDE_CONFIG_DIR`;
- Antigravity: `~/.local/state/big-red-agent-peer/antigravity-home` as its dedicated HOME.

OS keyring/DBus access is preserved so the providers can use their supported local login stores. Do
not inspect, export, screenshot, or copy those credential values.

## Invoke a peer

Run the wrapper inside an owner Git worktree below `~/Projects`.

Read/review only:

```bash
scripts/big-red-agent-peer review claude -- 'Review this change for correctness and missed cases.'
scripts/big-red-agent-peer review antigravity -- 'Review this change for correctness and missed cases.'
```

Edit the current task worktree:

```bash
scripts/big-red-agent-peer work claude -- 'Implement the requested fix. Do not run commands.'
scripts/big-red-agent-peer work antigravity -- 'Implement the requested fix. Do not run commands.'
```

Prompts may also arrive on stdin.

### Claude boundary

Claude runs with `--safe-mode`, so project/user customizations, hooks, plugins, MCP servers, skills,
and agent definitions do not load while subscription authentication still works. Review mode uses
`dontAsk` with only `Read,Glob,Grep`. Work mode uses `acceptEdits` but exposes only
`Read,Glob,Grep,Edit,Write`; the wrapper does not expose Bash.

Do not replace `--safe-mode` with `--bare` for this route. Claude's bare mode intentionally does not
use subscription OAuth/keychain credentials and is intended for API/provider credentials instead.

### Antigravity boundary

Antigravity always receives `--sandbox` and JSON headless output. Its dedicated HOME prevents
unrelated user-wide Antigravity settings, plugins, skills, or MCP configuration from silently
widening this peer session.

Antigravity auto-allows writes inside its active workspace. Therefore review mode exports the
current tracked and non-ignored worktree files into a disposable owner-only directory and destroys
that directory after the run. Escaping or absolute symlinks are refused during export. Work mode
runs in the real task worktree and may edit it.

Never add `--dangerously-skip-permissions` to this wrapper. Command/test execution remains with
Codex, Glaeda, or the operator, which keeps provider reasoning/edit authority separate from machine
execution authority.

## First smoke after login

Use a tiny non-mutating prompt first:

```bash
cd ~/Projects/glaeda
scripts/big-red-agent-peer review claude -- 'Reply with the repository name and one sentence about what it does.'
scripts/big-red-agent-peer review antigravity -- 'Reply with the repository name and one sentence about what it does.'
```

Then use one task-private worktree for an edit-only smoke and inspect the Git diff yourself. Run
verification through the repository's normal command or Glaeda rather than asking the peer CLI for a
broad shell.

## Operator boundary

Installing these CLIs and establishing new provider OAuth sessions are Big Red machine/account
mutations. Execute them only after the relevant change is reviewed and the operator has authorized
that action. Browser OAuth, passkeys, one-time codes, CAPTCHAs, and recovery flows remain human
boundaries.
