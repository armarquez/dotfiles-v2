# claude/

Claude Code configuration, managed as GNU Stow packages targeting `~/.claude/`.

`claude/` is the stow **dir** containing two packages — `base/` (always applied) and `airbnb/` (applied only on Airbnb machines). This mirrors the `50-`base / `80-`airbnb split in the zsh config.

## Packages

### `base/` — always stowed

| File | Lands in `~/.claude/` | Description |
|---|---|---|
| `settings.json` | `settings.json` | Base settings — privacy env vars, permission deny rules, hooks, statusline, general plugins. **Not symlinked** — merged with `airbnb/settings.json` (Airbnb env only) via `jq` and written as a real file by `stow`/`restow`. |
| `CLAUDE.md` | `CLAUDE.md` | Global development standards loaded into every session |
| `statusline.sh` | `statusline.sh` | Two-line statusline (model, folder, branch, context %, cost, duration) |
| `rules/diagrams.md` | `rules/diagrams.md` | Always use MermaidJS for diagrams |
| `rules/writing-style.md` | `rules/writing-style.md` | Concise, scannable technical writing standards |
| `rules/no-repetition.md` | `rules/no-repetition.md` | Single-source rule for docs |
| `rules/remediation-design.md` | `rules/remediation-design.md` | Audit → enforce rollout pattern |
| `rules/link-validation.md` | `rules/link-validation.md` | Validate all links before finalizing docs |
| `rules/substantiate.md` | `rules/substantiate.md` | Always back factual claims with verifiable evidence |

### `airbnb/` — stowed only on Airbnb machines

| File | Lands in `~/.claude/` | Description |
|---|---|---|
| `settings.json` | *(merged into `settings.json`, not symlinked)* | Airbnb-managed plugins: `datako@infrastructure-org`, `ssvc-tools@security` |
| `rules/ghe-access.md` | `rules/ghe-access.md` | Internal Git host routing and `gh` CLI usage |
| `rules/link-validation-airbnb.md` | `rules/link-validation-airbnb.md` | Internal fetch tooling addendum for validating internal URLs |
| `rules/substantiate-airbnb.md` | `rules/substantiate-airbnb.md` | Internal evidence sources for code, metrics, and stats |

**Encrypted at rest:** these three `rules/*.md` files contain Airbnb-internal domains, so their
plaintext is gitignored — only an age-encrypted ciphertext under `secrets/vault/` is committed (not
a sibling `.age` file — stow's `load-shell-fragments` would try to source it). Run `just decrypt-airbnb`
(from the repo root, prompts once for a passphrase) **before** `just claude stow`/`restow` — stow
needs the plaintext to exist. See the "Airbnb secrets" section in the root `CLAUDE.md` for the full
model, and `just encrypt-airbnb` to reseal after editing. The `zsh/zsh/.zshrc.d/80-airbnb-*.zsh`
fragments are covered by the same encryption scheme.

### Stow-dir level — never stowed

| File | Description |
|---|---|
| `justfile` | Claude recipes, surfaced from root as `just claude <recipe>` |
| `README.md` | This file |
| `.upstream/` | Committed baseline snapshots for 3-way upstream merge (one file per tracked upstream file) |

Runtime state (`sessions/`, `history.jsonl`, `cache/`, `projects/`, `plugins/`) lives in `~/.claude/` and is never touched by stow.

## Required tools

The recipes require `jq` (settings merge), `delta` (diff rendering), and assume `stow` is a system prereq. All are satisfied by any installer — `mise` is the easiest bootstrap:

```bash
# One-shot (installs just, jq, fzf, age, delta from .mise.toml at repo root):
mise install

# Or individually via brew / apt:
brew install jq stow git-delta
```

`check-upstream` falls back to `git diff --no-index --color` if `delta` is not installed.

`settings.json` is regenerated on every `stow`/`restow` — it is a real file, not a symlink, and is not tracked by git.

## Environment detection

The `stow` and `restow` recipes auto-detect Airbnb environment by checking (in order):
1. `command -v yak` (cloud dev workspace CLI)
2. `~/dev/airbnb` directory
3. `command -v airlab`
4. `~/.airlab` directory

Override for testing:
```bash
CLAUDE_FORCE_AIRBNB=1 just claude restow   # force Airbnb rules on
CLAUDE_FORCE_AIRBNB=0 just claude restow   # force Airbnb rules off
```

## Upstream source

Seeded from [armarquez/claude-code-config](https://github.com/armarquez/claude-code-config) (fork of Trail of Bits' template). Files are maintained directly here.

`claude/.upstream/` holds a committed snapshot of the last-synced upstream revision. This is the 3-way merge base: when upstream changes, only edits introduced *upstream* are applied — your local customizations survive automatically.

```bash
just claude check-upstream    # show what changed upstream since last sync (delta-rendered)
just claude sync-upstream     # pull upstream changes in, preserving local edits
```

## Recipes

| Recipe | Purpose |
|---|---|
| `just claude stow` | Link both packages into `~/.claude/` (backs up conflicts to `*.bak`); generates `settings.json` |
| `just claude restow` | Re-stow after adding files; also syncs Airbnb rules if env changed; regenerates `settings.json` |
| `just claude unstow` | Remove all stow-managed symlinks and generated `settings.json` from `~/.claude/` |
| `just claude gen-settings` | Regenerate `~/.claude/settings.json` without re-stowing (useful after editing source JSON) |
| `just claude check-upstream` | Show what changed upstream since last sync (delta-rendered, snapshot-vs-remote) |
| `just claude sync-upstream` | 3-way merge upstream changes into local files; advances the `.upstream/` baseline |
| `just claude check-upstream-raw` | Raw `diff` of local vs remote (no baseline filtering; original behavior) |

## Adding a rule

- **Universal rule:** drop in `base/rules/<name>.md`, run `just claude restow`.
- **Airbnb-only rule:** drop in `airbnb/rules/<name>.md`, run `just claude restow`.
