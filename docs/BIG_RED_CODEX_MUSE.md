# Big Red Codex + Muse profiles

Big Red can run Muse Spark 1.3 Contributor Free inside the Codex harness while
leaving its existing Codex + Sol default untouched. The profiles reuse the
operator's supported local OpenCode Zen credential through Codex's
command-backed custom-provider authentication.

## Contract

- Provider id: `opencode_zen`
- Provider name: `OpenCode Zen`
- Base URL: `https://opencode.ai/zen/v1`
- Wire API: `responses`
- Model: `muse-spark-1.3-contributor-free`
- Profiles: `muse-high` and `muse-xhigh`
- Credential owner: the local OpenCode credential store
- Existing Codex base config/default: unchanged

The current Zen Responses endpoint accepts reasoning effort through `xhigh`,
which is the highest configured profile. The installer removes the earlier
managed `muse-max` profile if present; it never aliases or silently downgrades an
unsupported effort name.

The reviewed token helper reads the existing OpenCode `opencode` API credential
only when Codex requests a bearer token. No credential value is copied into a
profile, shell startup file, repository, receipt, or workspace prose.

The Muse profiles disable Codex Apps, Plugins, and Multi-agent only for those
profiled sessions. Those features expose recursive namespace-tool schemas that
the current Zen/Muse route rejects. Codex's normal shell, file-editing, planning,
and other compatible function tools remain available. Unprofiled Sol sessions
retain the machine's existing feature set.

## Install and verify

Run from the reviewed `compute-node-bootstrap` checkout on Big Red:

```bash
scripts/install-big-red-codex-muse --plan
scripts/install-big-red-codex-muse
scripts/install-big-red-codex-muse --verify-only
```

The apply step installs three mode-0600 layered profile files under `~/.codex`
and the reviewed token helper under `~/.local/libexec`. Codex's base
`~/.codex/config.toml` is not edited.

## Use

Interactive:

```bash
codex -p muse-high
codex -p muse-xhigh
```

Non-interactive:

```bash
codex exec -p muse-high -- 'Inspect this repository and run useful checks.'
```

Without `-p muse-*`, ordinary Codex continues using the existing Sol default.
The separate `big-red-muse-peer` command continues to provide OpenCode + Muse.

## Failure boundary

The profiles pin the exact Contributor Free model and do not define a fallback.
If OpenCode Zen removes the route or rejects the credential, Codex fails visibly
instead of selecting Sol, another provider, or a paid model.
