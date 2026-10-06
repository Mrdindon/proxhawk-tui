# Analysis: devnullvoid/pvetui compared with this project

Source analysed: <https://github.com/devnullvoid/pvetui> (snapshot of
2026-10-03, v1.4.4, MIT licence, created 2025-05-03, ~730 stars).
Analysed on 2026-10-06. **No code of this project was changed**: this file
only documents ideas. In this file "pvetui" is the other project, except in
the column "this project" (renamed **pvetty** in 1.2.0).

## 1. Overview of the other project

| Item | devnullvoid/pvetui | this project (pvetui 1.0.0, now pvetty) |
|------|--------------------|-----------------------------|
| Language / size | Go, ~70 000 lines, 450 files; tview + tcell | bash + one Perl helper, ~10 000 lines |
| Where it runs | on the **client** (Linux, macOS, Windows), talks to the HTTPS API | **on the Proxmox node**, local API stack as root (no network, no token) |
| Authentication | API token or password, renewal, several profiles, SOPS/age encrypted config | none needed (local `root@pam`) |
| UI model | own UI: pages *Nodes / Guests / Tasks / Storage*, context menu (`m`), global menu (`g`/`Esc`), vim keys | copy of the web GUI: tree, per-object menus, toolbars, every GUI panel |
| Configuration coverage | guest lifecycle, create VM/LXC, snapshots, backups, migration, storage content, tasks; few datacenter settings | every menu of the GUI (Datacenter, Node, VM, CT, Storage, Pool, SDN), read/write, schema-driven forms |
| Consoles | SSH to nodes/VMs/CTs (jump host), embedded **noVNC** in the browser | `qm terminal`, SSH (IP discovery), `pct enter`, node shell |
| Multi-cluster | profiles + *group mode* (aggregate several clusters, or active/passive failover) | one node / one cluster |
| Non-interactive | **CLI subcommands** with JSON output (`pvetui guests list`, `start`, `migrate`...) + a Claude Code skill | none |
| Extensibility | opt-in plugins (Ansible, Community Scripts, command runner, guest insights) | `views/*.sh` modules |
| Tests | Go unit tests, mock PVE API server, VHS terminal recordings with golden files, CI, golangci-lint | self test + read/write integration tests against a real node (703 checks) |
| Distribution | binaries, .deb/.rpm, Cloudsmith repo, AUR, Homebrew, Scoop, Docker, Nix, goreleaser | tarball + install.sh |

### Was it generated with an AI?

Signs of an **AI-assisted** development, but not proof of a fully generated
project:

- `AGENTS.md` (29 KB of instructions for coding agents: workflow, standards,
  pitfalls, architecture decisions) and a `CLAUDE.md` that only says "read
  AGENTS.md" (`AGENTS.md` is the Codex/agents convention, `CLAUDE.md` the
  Claude Code one);
- a `skills/pvetui-cli/SKILL.md` installable in Claude Code (`npx skills add`);
- very regular commit messages, changelog and documentation style.
- On the other hand, none of the last 300 commits carries a
  `Co-Authored-By: Claude` (or other agent) trailer, the project exists since
  May 2025 with external contributors, issues and releases: it is a
  human-maintained project developed with AI agents (probably several:
  Claude Code and Codex), not a one-shot generation.

### Name collision

Both projects are called **pvetui** and use `~/.config/pvetui/`. Theirs uses
`config.yml`, ours `pvetui.conf`, so the files do not collide, but the
command name and the directory do. **To decide before any publication**:
rename ours (e.g. `pveconsole`, `pvegui-tui`, `proxtui`) or keep it private.

**Resolved in 1.2.0**: this project is now **pvetty** (`pvetty` command,
`~/.config/pvetty/pvetty.conf`, `PVETTY_*` variables); the old user
configuration is migrated automatically. Names containing "Proxmox" were
avoided: the Proxmox trademark guidelines do not allow it in product names.

## 2. How they handle fonts and icons

They do **not** use Nerd Fonts at all.

- Icons are **standard Unicode emoji**: 🟢 🔴 (status), 📦 (container),
  💾 (backup), ⚠️ ❌ ✅ (messages), ⚡, and 🗘 (U+1F5D8) for a pending
  operation. These are drawn by the colour emoji font that every desktop
  already has (Noto Color Emoji, Segoe UI Emoji, Apple Color Emoji) through
  the font fallback of the terminal, so **no font installation is needed**.
- Widths are handled by the library: tview/tcell use go-runewidth / uniseg to
  know that an emoji takes 2 cells (`tview.TaggedStringWidth`), so the
  alignment stays correct.
- One switch, `show_icons` (config file, `--show-icons`,
  `PVETUI_SHOW_ICONS`, or *Global menu › Application Settings*), removes the
  **decorative** icons (message prefixes, menus, startup messages). Status
  indicators and spinners stay visible (coloured text).
- Implementation: two helpers, `IconText(icon, text, showIcons)` and
  `GetIconLabel(label, icon, showIcons)`, called everywhere an icon is shown.
- Colours: semantic colours mapped by default to the terminal ANSI palette
  (the terminal theme applies), with named themes and hex overrides.

### What it means for us

| Option | Pros | Cons |
|--------|------|------|
| Keep Nerd Font / Unicode / ASCII (current) | exact web UI icons with a Nerd Font, single-cell characters (our width computation is `${#s}`) | Nerd Font must be installed on the client terminal (squares otherwise) |
| Add an **emoji** icon set like theirs | works on most desktops without installing a font | emoji are 2 cells wide: `fit`/`vlen` need a width table (wcwidth) for the characters used; rendering of emoji differs between terminals; not available on the Linux console |
| Add an **`icons = off`** switch | simplest fallback, like `show_icons: false` | fewer visual cues |
| Startup **glyph test**: print a glyph and read the cursor position (`ESC [6n`) | detects terminals that draw a glyph in 2 cells, could choose a safe set automatically | cannot detect a missing glyph (a square is 1 cell too) |

Recommendation: keep `unicode` as default (it needs no special font and is
single-cell), add `icons = off`, and optionally an `emoji` set restricted to a
small list of characters whose width is declared in the glyph file (so `fit`
can account for 2-cell characters without a full wcwidth implementation).

## 3. Improvements that could be transposed

Effort: S = small (< 1 day), M = medium, L = large. Fit = how well it fits our
"on the node, minimal footprint, copy of the GUI" goals.

### User interface

| # | Idea (from their code) | What it would be in ours | Effort | Fit |
|---|------------------------|--------------------------|--------|-----|
| 1 | **Pending operation indicator** (🗘 next to the guest while an action is in flight, `FormatPendingStatusIndicator`) | mark the tree entry / grid row of a guest that has a running task started by pvetty (we already track `TASK_WATCH`) | S | high |
| 2 | **Per-guest task queue** (`internal/taskmanager`: one active task per node/VMID, next ones queued, cancel queued, max running) | queue actions on a guest that already has a running task instead of failing on the lock; show the queue in the Tasks panel | M | high |
| 3 | **Batch selection** (Space marks several guests, *Batch Actions* menu: start/stop/shutdown/restart...) | Space in the Search grids marks rows; `m` offers batch actions (one task each, through the queue) | M | high |
| 4 | **Configurable key bindings** (`key_bindings` section, help generated from it, `Alt`/`Ctrl` combos) | `[keys]` in the config file mapping actions to keys; help screen built from the map | M | medium |
| 5 | **Help modal** listing every key of the current context | `?`/`F1` currently opens USAGE.md in `less`; an overlay listing the keys of the focused panel (from `VIEW_HINT`, toolbar and CRUD) would be faster | S | high |
| 6 | **Auto-refresh toggle with countdown** in the footer (`a`), paused while loading or during operations | key to pause/resume refresh, countdown in the footer | S | medium |
| 7 | **Advanced filter** for guests (status / node / type) and search state kept when changing page | filter dialog for the Search grids (`f`), keep `SEARCH_TERM` per type | S | high |
| 8 | **Named themes** (dracula, nord, gruvbox, catppuccin, solarized, tokyonight, kanagawa, everforest, rose-pine) + per-colour overrides in hex or `default` | more `themes/*.sh`; allow `#rrggbb` (truecolor `38;2;r;g;b`) and colour overrides in the config file | S | medium |
| 9 | **Application Settings** screen (icons, startup page, quiet startup, refresh, confirm quit) | extend the `F4` menu: refresh interval, task panel height, tree width, startup selection, confirm quit, all saved | S | high |
| 10 | **Startup page** option (`--startup-page`) | we have `--select`; add a config key `startup = qemu/100` / last position restore | S | medium |
| 11 | **Guest list sorted with running first, IP column** (agent / neighbour) | IP column in the guest grids (we already have the discovery code for SSH) | S | high |
| 12 | **Confirm quit** when sessions/tasks are active | ask before quitting if `TASK_WATCH` / background jobs exist | S | high |

### Consoles and access

| # | Idea | In ours | Effort | Fit |
|---|------|---------|--------|-----|
| 13 | **noVNC console** (embedded noVNC + local websocket proxy, opens the browser) | without embedding anything: show / copy (OSC 52) or make clickable (OSC 8 hyperlink) the URL of the GUI console of the guest, `https://<node>:8006/?console=kvm&novnc=1&vmid=<id>&node=<node>` | S | high |
| 14 | **SSH options**: `ssh_user`, `vm_ssh_user`, key files, **jump host** | config keys for the SSH console of VMs (user, key, jump host `-J`) | S | high |
| 15 | **Guest agent exec** (`guests exec 100 "uptime"`) | action *Run command (guest agent)* on VMs: `POST /nodes/N/qemu/ID/agent/exec` + `exec-status`, output in the task viewer style window | S | high |

### Architecture and scope

| # | Idea | In ours | Effort | Fit |
|---|------|---------|--------|-----|
| 16 | **CLI subcommands** with JSON / table output (`pvetui nodes list`, `guests start 100`, `--no-wait`...) | `pvetty cli <path> ...` reusing the broker (JSON already available) and `api_exec` for writes; useful for scripts and AI agents (with a skill/README for agents) | M | high |
| 17 | **Remote mode / profiles** (HTTPS API with token, several profiles) | an HTTPS backend with `curl` + API token (curl is installed on PVE) so pvetty can run from another Linux machine; profiles in the config | L | medium (changes the "local root" design) |
| 18 | **Group mode** (several clusters in one view, active/passive failover) | only after #17 | L | low |
| 19 | **Plugin system** (opt-in, enabled in the config / manager dialog) | load `~/.config/pvetty/plugins/*.sh` (views, toolbar actions) only when enabled; examples: community scripts installer, Ansible inventory export | S | high |
| 20 | **Persisted cache** (file cache with TTL + LRU, Badger) | not needed with the broker (5 ms per read); could cache the API schema between runs | S | low |
| 21 | **Config secrets encryption** (SOPS/age) | only relevant with #17 (tokens) | M | low |
| 22 | **Onboarding / first-run wizard** | first run: choose icons (with preview), theme, language, mouse | S | medium |
| 23 | **Log file with levels** (`--debug`) | we have `PVETTY_DEBUG`; add levels and log rotation | S | low |

### Quality, tests and distribution

| # | Idea | In ours | Effort | Fit |
|---|------|---------|--------|-----|
| 24 | **Mock PVE API server** (`cmd/pve-mock-api`, `pkg/mockpve`) for tests without a cluster | a *replay* backend for the broker: answers from recorded JSON fixtures, so the UI and the forms can be tested anywhere (CI, laptops) | M | high |
| 25 | **Golden terminal tests** (VHS tapes + golden text output) | tmux based: run scripted key sequences, `capture-pane`, compare with golden files (we did it by hand during development) | S | high |
| 26 | **Lint + CI** (golangci-lint, pre-commit, GitHub Actions) | `shellcheck` + `perlcritic` + selftest in a pre-commit hook / CI | S | high |
| 27 | **Packaging** (.deb/.rpm, repository, Homebrew...) | a `.deb` (`pvetty_1.1.0_all.deb`, depends on `pve-manager`, installs into `/usr/share/pvetty` + `/usr/bin/pvetty`) | S | high |
| 28 | **AGENTS.md / CLAUDE.md** for AI contributors | our `docs/DEVELOPMENT.md` already plays this role; a short `AGENTS.md`/`CLAUDE.md` pointing to it and to the test rules would help AI-assisted maintenance | S | high |
| 29 | **LICENSE, CONTRIBUTING, THIRD_PARTY_LICENSES, RELEASING** | we have no licence file: choose one before sharing | S | high |
| 30 | **Screenshots / demo recordings** (VHS tapes) | text screenshots from tmux (already in README), a recorded demo (asciinema) | S | low |

## 4. What this project already does that theirs does not

To keep in mind when choosing what to transpose:

- runs directly on the node: no token, no network setup, no install;
- the same structure and every menu of the web GUI, including Datacenter
  configuration, permissions, HA, SDN, firewall, ACME, Ceph, disks,
  notifications, mappings;
- dialogs generated from the API schema (new PVE options appear without code);
- task viewer like the GUI (live output, Stop, refresh on close);
- braille RRD graphs and gauges;
- read/write integration tests against a real node.

## 5. Suggested order

1. Quick wins with high fit: #1 pending indicator, #5 help overlay, #7 guest
   filter, #9 settings screen, #11 IP column, #12 confirm quit, #13 console
   URL, #14 SSH options, #15 guest agent exec, `icons = off` (section 2).
2. Workflow: #2 task queue, #3 batch selection.
3. Tooling: #25 golden tmux tests, #26 shellcheck/CI, #27 .deb, #28 AGENTS.md,
   #29 licence, and decide the name (section 1).
4. Larger: #16 CLI subcommands, #24 replay backend, #19 plugins.
5. Only if pvetty must run outside the node: #17 remote mode (then #18, #21).
