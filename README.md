# Asher

**Asher makes it easy to contribute to a whole GitHub organization's repos.**

Point it at an org (the [Ash ecosystem](https://github.com/ash-project) — ~50 active
Elixir repos — is the flagship example), and asher links every repo, clones them so
you can `cd` straight in, and turns *"I want to fix this issue"* into a branched,
forked, pushed **draft PR** in one interactive command.

The org is a parameter, not a hard-coded assumption: `asher setup <org>` works for any
GitHub organization. `ash-project` is just the default.

Asher ships two ways to run, sharing the same engine:

- **`asher`** — a standalone CLI (an Elixir escript) you install globally.
- **`mix asher.*`** — the same commands as composable [igniter](https://igniter.hexdocs.pm/)
  mix tasks, for use inside the cloned asher repo.

---

## What it does

1. **`asher setup ash-project`** — fetches the org's active repos (skipping archived
   repos, forks and `.github`), writes them to a manifest (`priv/repos.json`), and clones
   them into the current directory as full, independent git repos so you can `cd ash` and
   work.

2. **`asher init`** — runs an interactive survey and scaffolds a contribution:
   - *Does it have an issue?* If so, paste the link and asher **scrapes** its title and
     labels (via `gh`) to suggest a category and a name.
   - *What kind of contribution?* — feature / enhancement / bug fix / improvement /
     documentation.
   - *Which repo(s)?* — pick one or more from the tracked repos.
   - *Name it* — with a slug suggested from the issue title.

   Then, for each selected repo, it: branches off the default branch, forks the repo to
   your account, pushes the branch to your fork, and opens a **draft PR** that references
   the issue (`Closes #N`). A receipt with everything it gathered is written under `data/`.

3. **`data/`** becomes a dashboard of your in-flight contributions — one folder per
   contribution (e.g. `data/add-upsert-support (ash, ash_sql)/`) holding a human-readable
   `contribution.md` and a machine-readable `contribution.json`.

---

## Requirements

- **Elixir** `~> 1.20` (and Erlang/OTP to match) — to build/install the escript
- **git**
- **GitHub CLI `gh`**, installed and authenticated, for `init`. Install it for
  [Windows](https://cli.github.com/) or [WSL/Ubuntu](https://www.freecodecamp.org/news/github-cli-wsl2-guide/), then:
  ```sh
  gh auth login
  ```
  `init` checks for it up front and stops with instructions if it's missing or
  unauthenticated. (`setup`/`sync` only need `curl` and the public API.)

---

## Install

### Option A — global `asher` command (recommended)

Install the escript straight from GitHub:

```sh
mix escript.install github <your-fork-or-org>/asher
```

That builds and installs an `asher` binary into your Mix **escripts** directory. The next
step is to make `asher` runnable from anywhere — see below — then:

```sh
mkdir ash-contribs && cd ash-contribs
asher setup ash-project
asher init
```

#### Put `asher` on your `PATH`

First, find where the binary was installed (works on every setup):

```sh
mix escript
# → Escripts installed at: /path/to/.mix/escripts
```

- Plain installs: `~/.mix/escripts`
- **asdf**: a *per-Elixir-version* directory, e.g. `$(asdf where elixir)/.mix/escripts`
  (so `asher` is tied to the Elixir version you installed it under)
- **mise**: `"$(mise where elixir)/.mix/escripts"`

**Quick way (any shell): symlink into a `bin` dir that's already on your `PATH`.** Many
systems already have `~/.local/bin` on `PATH`:

```sh
mkdir -p ~/.local/bin
ln -sf "$(asdf where elixir)/.mix/escripts/asher" ~/.local/bin/asher   # asdf
# non-asdf: ln -sf "$HOME/.mix/escripts/asher" ~/.local/bin/asher
```

Or add the escripts directory to your `PATH` in your shell's startup file:

**zsh / oh-my-zsh** — add to `~/.zshrc` (or drop it in `~/.oh-my-zsh/custom/asher.zsh`,
which oh-my-zsh auto-loads), then `source ~/.zshrc`:

```sh
# asdf (version-aware):
export PATH="$PATH:$(asdf where elixir)/.mix/escripts"
# non-asdf:
# export PATH="$PATH:$HOME/.mix/escripts"
```

**bash** — the same lines in `~/.bashrc` (also `~/.bash_profile` or `~/.profile` for login
shells, e.g. fresh WSL terminals), then `source ~/.bashrc`.

**fish** — in `~/.config/fish/config.fish`:

```fish
fish_add_path (asdf where elixir)/.mix/escripts   # asdf
# fish_add_path $HOME/.mix/escripts               # non-asdf
```

Verify:

```sh
asher --version
```

> **asdf/mise tip:** escripts install *per language version*, so switching Elixir versions
> means `asher` won't be found until you reinstall it under the new version. To install
> escripts to one stable, version-independent location, set `export MIX_HOME="$HOME/.mix"`
> in your shell rc (before running mix), reinstall with `mix escript.install github …`, and
> put `$HOME/.mix/escripts` on your `PATH`.

### Option B — clone and use the mix tasks

```sh
git clone https://github.com/<you>/asher && cd asher
mix deps.get
mix asher.setup ash-project
mix asher.init
```

---

## Commands

The escript (`asher <cmd>`) and the mix tasks (`mix asher.<cmd>`) are equivalent.

### `setup <org> [repo ...]`
Sync an org's active repos into the manifest **and clone them**. Idempotent.

```sh
asher setup ash-project                    # all active repos
asher setup ash-project ash ash_postgres   # only these
asher setup ash-project --lang elixir      # only Elixir-language repos
asher setup ash-project --no-clone         # sync the manifest only
asher setup https://github.com/acme        # any org, by URL
```

### `init [--dry-run]`
The headline command: interactive survey → branch → fork → push → **draft PR** →
`data/` receipt. Run it in a terminal. `--dry-run` walks the survey and prints the plan
without creating branches, forks, PRs or files.

### `sync <org>`
Regenerate the manifest for an org without cloning. Re-running an org replaces its
entries; a new org is appended. Keeps the managed clone-ignore block in `.gitignore` in
sync. (As a mix task this is `mix asher.repos.sync`.)

```sh
asher sync ash-project --lang elixir --include ash_hq --exclude quix
```

### `status`
Read-only dashboard of every contribution recorded under `data/`.

---

## How it works

- **Manifest (`priv/repos.json`)** — a flat list of tracked repos (across one or more
  orgs) with `org`, `name`, `full_name`, `clone_url`, `description`, `language`,
  `archived` and `fork`. Generated from the GitHub API with a reproducible active-repo
  filter.
- **Clones** — live in the workspace as independent git repos, gitignored via a managed
  block that tracks the manifest.
- **Fork-based flow** — asher forks each target repo to your account, pushes the branch to
  the fork, and opens the draft PR `your-fork:branch → org:default-branch`. Branch names
  are `<category-prefix>/<slug>` (e.g. `fix/broken-thing`). GitHub needs a diff to open a
  PR, so asher makes one empty commit to start the branch.
- **Receipts (`data/`)** — record what contributions are in flight, with links to each PR.

Internally, the igniter-free core (`Asher.Survey`, `Asher.Github`, `Asher.Git`,
`Asher.Manifest`, `Asher.Contribute`) is shared by both the escript (`Asher.CLI`, writing
files via `Asher.FS`) and the mix tasks (writing files via igniter). Every external
command goes through `Asher.Shell`, which is what makes the whole tool testable offline.

---

## Development & testing

```sh
mix deps.get
mix test                         # unit tests (pure logic, stubbed gh/git, full survey flow)
mix test --include integration   # also run a live, read-only sync against ash-project
MIX_ENV=prod mix escript.build   # build the ./asher binary locally (as escript.install does)
```

The unit suite stubs every external command, so it never touches the network or your
filesystem. The integration test (tagged, excluded by default) verifies the real
`ash-project` org fetch + filter.
