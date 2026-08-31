# Big Red Jujutsu (`jj`) experiment bootstrap

This runbook installs the pinned Jujutsu binary needed by the Big Red agent-workflow experiments.

Research owner: `teamleaderleo/leo-workspace#357`
Product follow-up: `teamleaderleo/glaeda#969`

The install itself changes no repository. Converting or colocating a real checkout is a separate measured experiment.

## Pinned release

```text
Jujutsu: 0.44.0
platform asset: jj-v0.44.0-x86_64-unknown-linux-musl.tar.gz
archive SHA-256: 0a07bab4641a55fd2bc2fd1563ba3a3f9a577584086ad74086a1c5b69b3ffce9
minimum Git: 2.41.0
```

The asset/digest comes from GitHub's release metadata for upstream `jj-vcs/jj` v0.44.0.

Upstream references:

- https://github.com/jj-vcs/jj/releases/tag/v0.44.0
- https://github.com/jj-vcs/jj/blob/main/docs/install-and-setup.md
- https://github.com/jj-vcs/jj/blob/main/docs/git-compatibility.md
- https://github.com/jj-vcs/jj/blob/main/docs/github.md

## Plan

From this repository on `big-red`:

```bash
bash scripts/install-big-red-jj --plan
```

The plan prints only the operator, pinned JJ/Git versions, source-archive identity, and relative managed paths.

## Install

```bash
bash scripts/install-big-red-jj
```

The installer:

1. requires Git >= 2.41.0 and the fixed host tools used by the install;
2. downloads the exact v0.44.0 x86-64 Linux musl release archive over HTTPS;
3. verifies the pinned SHA-256 before extraction;
4. rejects path-traversal archive members;
5. requires exactly one regular file named `jj` in the extracted release;
6. installs it under:

   ```text
   ~/.local/lib/big-red-tools/jj/v0.44.0/jj
   ```

7. publishes only this managed launcher:

   ```text
   ~/.local/bin/jj
   ```

8. verifies the installed version and prints the installed binary SHA-256.

An existing foreign `~/.local/bin/jj` or pre-existing managed version root causes refusal rather than replacement.

## Verify later

```bash
bash scripts/install-big-red-jj --verify-only
```

The verification confirms:

- current Git still satisfies the pinned minimum;
- the exact versioned managed binary exists and is executable;
- the launcher remains a symlink to that exact binary;
- `jj --version` reports the expected release;
- the installed binary digest is observable.

## Configure operator identity

After the install succeeds, inspect the already-accepted Git identity:

```bash
git config --global --get user.name
git config --global --get user.email
```

Then set the same values explicitly for Jujutsu:

```bash
jj config set --user user.name "$(git config --global --get user.name)"
jj config set --user user.email "$(git config --global --get user.email)"
```

Inspect:

```bash
jj config get user.name
jj config get user.email
```

The installer deliberately leaves JJ configuration alone. Repository-specific aliases, fix tools, Git/JJ policy, and experimental behavior belong to the measured R&D lane.

## Disposable smoke test

Use a temporary Git repository before touching a canonical clone:

```bash
root=$(mktemp -d ~/.cache/jj-smoke.XXXXXX)
trap 'rm -rf "$root"' EXIT
cd "$root"

git init smoke
cd smoke
git config user.name "$(git config --global --get user.name)"
git config user.email "$(git config --global --get user.email)"
printf 'hello\n' > hello.txt
git add hello.txt
git commit -m 'smoke base'

jj git init
jj status
jj log -r @ -n 1
jj git colocation status

git status --short --branch
git rev-parse HEAD
```

Current Jujutsu creates Git-backed workspaces in colocated mode by default. The smoke test should show both `.git` and `.jj` in this temporary repository and leave the underlying Git objects readable through ordinary Git commands.

Remove only the temporary root after inspection.

## First real-repository experiment

Follow `leo-workspace#357` rather than improvising on a canonical clone.

Before `jj git init` in a selected real repository, capture the experiment's required Git identity/cleanliness/feature receipt. In particular, classify current JJ compatibility for `.gitattributes`, submodules, Git LFS, partial clones, and any existing Git-worktree topology.

The intended initial posture is:

```text
Git/GitHub = cross-machine/publication boundary
.jj = machine-local editing/history convenience
Glaeda receipt = exact execution evidence bound to Git OIDs
```

Do not synchronize a live `.jj` repository between machines. Exchange work through Git/GitHub.

## Remove the managed binary

```bash
bash scripts/install-big-red-jj --remove
```

Removal is intentionally narrow. It removes the managed launcher only when it resolves to the pinned managed binary, then removes the exact version directory only when it contains no unexpected entries.

This command leaves:

- Git and Git configuration;
- GitHub SSH configuration;
- JJ user configuration;
- repository-local `.jj` directories created by later experiments;
- all Git repositories;

unchanged.

Repository-local JJ rollback belongs to the experiment that created that state.
