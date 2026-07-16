# dotfiles — agent guidance

## What this repo is

- **GNU Stow + git subtree + justfile.** `zsh/` is a vendored git subtree of [zsh-quickstart-kit](https://github.com/unixorn/zsh-quickstart-kit). `zsh/zsh/` is the Stow package whose contents map directly into `$HOME`.
- **`claude/` is the Claude Code config package**, stowed into `~/.claude/`. It is fully owned — seeded once from the [armarquez/claude-code-config](https://github.com/armarquez/claude-code-config) fork (upstream: Trail of Bits), then maintained directly here. Not a subtree.
- **Single `main` branch for both personal and work machines** — environment-detection inside fragments handles the split at runtime.

## Critical conventions

- **Never edit files inside `zsh/` except `zsh/zsh/.zshrc.d/`.** Everything else in `zsh/` is upstream kit — `just update-zsh` will clobber hand-edits. All customization goes in fragment files under `zsh/zsh/.zshrc.d/`.
- **Fragment numbering = load order** (files are sourced alphanumerically):
  - `50-` prefix → base config, loaded on every machine.
  - `80-` prefix → Airbnb/work config, self-gated (see below).
- **Airbnb fragments self-skip on personal machines** via `_is_airbnb_env` at the top of each `80-*` file. It checks for `yak`/`airlab` CLIs, `~/dev/airbnb`, or `~/.airlab`, then calls `return 0` to bail out early if not a work env. Never create a work-only branch; use this pattern instead.
- **New fragments must be self-contained.** Each fragment redefines `can_haz()` locally and carries the BSD-licensed header comment matching the existing files. Match that style exactly.
- **Stow symlinks are live.** Edits to existing fragment files take effect immediately after the next shell reload — no `just stow` needed. Only run `just restow` after *adding* a new file to the package.

### Claude config (`claude/`)

See `claude/README.md` for the full layout and recipe reference. Key agent-facing rules:

- **`claude/` is the stow *dir* containing two packages** — `base/` (always stowed) and `airbnb/` (stowed only when an Airbnb env is detected). Both target `~/.claude/` and their `rules/` contents merge into `~/.claude/rules/`.
- **Rules gate at stow time, not runtime.** Unlike zsh fragments (which `source` + `return 0` early), Claude rules are static markdown loaded by presence. The Airbnb gate is applied when stowing — `ghe-access.md` and `substantiate.md` only land in `~/.claude/rules/` on Airbnb machines.
- **Detection mirrors `_is_airbnb_env` from `80-airbnb.zsh`** (`yak`, `~/dev/airbnb`, `airlab`, `~/.airlab`). Use `CLAUDE_FORCE_AIRBNB=1/0` to override.
- **`settings.json` is a generated file, not a symlink.** `base/settings.json` (general plugins, env, hooks, permissions) is deep-merged with `airbnb/settings.json` (Airbnb-managed plugins only) via `jq` on every `stow`/`restow`, writing a real file to `~/.claude/settings.json`. Only two keys live in `airbnb/settings.json`: `enabledPlugins` for `datako@infrastructure-org` and `ssvc-tools@security`. `jq` is a required tool — already a runtime dependency of the hooks in `settings.json`.
- **`justfile` and `README.md` live at the stow-dir level** (in `claude/`, not inside `base/` or `airbnb/`), so they're never packaged and never appear in `~/.claude/`. `--ignore='settings.json'` is passed to all `stow`/`restow`/`unstow` calls so stow never manages it as a symlink.
- **`claude/justfile` recipes** are surfaced from the root via `mod claude` as `just claude <recipe>`. Zsh recipes stay in the root justfile — a justfile inside `zsh/` would be in the subtree path and could be clobbered by `just update-zsh`.
- **Upstream sync model:** `claude/.upstream/` holds committed snapshots of the last-synced upstream revision. `just claude check-upstream` shows only what *upstream* changed (snapshot vs remote, delta-rendered) — your local customizations are invisible. `just claude sync-upstream` does a 3-way `git merge-file` (base=snapshot, ours=local, theirs=remote) so local edits survive. Only genuine conflicts require manual resolution. Run `just claude restow` afterward.

## Common commands

| Command | Purpose |
|---|---|
| `just init` | One-time bootstrap (zgenom, stow, fzf, just) |
| `just stow` / `restow` / `unstow` | Manage `$HOME` zsh symlinks |
| `just claude stow` / `restow` / `unstow` | Manage `~/.claude/` symlinks |
| `just claude check-upstream` | Show upstream-only changes since last sync (delta-rendered) |
| `just claude sync-upstream` | 3-way merge upstream changes, preserving local edits |
| `just update-zsh` | Pull upstream kit subtree from GitHub |
| `just update-plugins` / `regen` | Update / regenerate zgenom plugins |
| `just startup` | Per-session cloud-workspace setup |
| `just sync` | Pull from public `origin`, push to work `ghe` |
| `just push-all` | Push to both remotes |

## Two-remote sync model

- `origin` → `github.com/armarquez/dotfiles` (public)
- `ghe` → internal work Git host (work)
- Standard workflow: commit to `main`, then `just push-all` or `just sync`.

## Tooling

- **Plugin manager:** zgenom (cached at `~/.zgenom`, configured via `~/.zgen-setup`)
- **Prompt:** powerlevel10k (`just p10k` to reconfigure)
- **Runtime managers:** pyenv, jenv (lazy), rbenv, nvm, GVM, and **mise** (preferred — used for Go and Airbnb shims)
- **Other:** direnv, fzf, tig, pygitup
- **Bootstrap tools:** `.mise.toml` at repo root pins `just`, `jq`, `fzf`, `age`, and `delta` (current stable versions). `mise install` provisions all of them; brew/apt also work. `stow` is not in the mise registry and stays a system prereq. `.init.sh` uses `_ensure_tool` — checks presence first (regardless of installer), reaches for mise/brew/apt only when a tool is missing.

## Airbnb secrets (age-encrypted at rest)

`claude/airbnb/rules/*.md` and `zsh/zsh/.zshrc.d/80-airbnb-*.zsh` contain Airbnb-internal domains,
an LDAP username, and a work email — sensitive enough to keep out of plaintext in this public repo.

- **Plaintext is gitignored; only `.age` ciphertext under `secrets/vault/` is committed.** The six
  in-scope files are listed in `justfile`'s `AIRBNB_FILES` variable. Ciphertext mirrors the
  plaintext's relative path (e.g. `zsh/zsh/.zshrc.d/80-airbnb.zsh` → `secrets/vault/zsh/zsh/.zshrc.d/80-airbnb.zsh.age`)
  rather than sitting as a sibling — `load-shell-fragments` in `zsh/zsh/.zshrc` sources every
  readable file in `~/.zshrc.d` with no extension filter, so a sibling `.age` file gets sourced as
  shell code and produces garbage errors on shell startup.
- **Key model:** `secrets/airbnb.recipient` is the public age key (committed, not secret — used to
  encrypt, no password needed). `secrets/airbnb-identity.age` is the matching private key, itself
  passphrase-encrypted (committed — decrypting it is the only password-protected step).
- **`just encrypt-airbnb`** seals plaintext → `secrets/vault/.../*.age` after editing an Airbnb rule
  or zsh fragment. No password required.
- **`just decrypt-airbnb`** unseals `secrets/vault/` ciphertext → plaintext on a new machine. Prompts
  for the passphrase exactly once, then reuses the unlocked identity for all files. **Run this before
  `just claude stow` or `just restow`** — those recipes link/source the plaintext files, which won't
  exist yet otherwise.
- **New sensitive Airbnb content must be sealed (`just encrypt-airbnb`) before committing.** Never
  commit the plaintext identity (`age-keygen` output) — only the passphrase-sealed `.age` form.
