# Changelog

## 1.2.0 — 2026-10-06

- **Renamed pvetui → pvetty** (PVE + TTY): another project is called pvetui.
  Command `pvetty`, files `~/.config/pvetty/pvetty.conf`, `/etc/pvetty.conf`,
  `~/.local/state/pvetty/`, variables `PVETTY_*`, package `pvetty`. The user
  files of pvetui are moved automatically at the first start;
  `/etc/pvetui.conf` is still read while `/etc/pvetty.conf` does not exist.
  Variables `PVETUI_*` are no longer read.
- **Licence**: GNU AGPL v3.0 or later (`LICENSE`).

## 1.1.0 — 2026-10-06

Improvements inspired by the analysis of devnullvoid/pvetui
(docs/COMPARISON-devnullvoid-pvetui.md). Local node only, as before.

- **Help window** (`F1` / `?`): keys of the current panel, toolbar, global
  keys; the user guide moved to `F7`.
- **Configurable key bindings** (`key.<action>`) and **colour overrides**
  (`color.<token>`: `#hex` with truecolor or nearest 256 colours, ANSI names,
  attributes); six new themes (dracula, nord, gruvbox, catppuccin-mocha,
  solarized-dark, tokyonight); `icons = 0` (no icons).
- **Application Settings** screen (`F4`) for every setting; first run
  wizard (icons with preview, theme, mouse); `startup = last` restores the
  previous selection; confirmation before quitting with running actions.
- **Action queue**: actions on a busy guest are queued and start when it is
  free; queued actions in the Tasks panel, `x` cancels them or stops a task;
  spinner on guests with a running task (tree and title).
- **Batch actions** in the search grids: `Space` marks guests, `m` runs
  start / shutdown / stop / reboot / suspend / resume / backup on them;
  `f` filters by status / type / node / tag; **IP column**.
- **Run command** in a guest (agent / `pct exec`), **browser console URL**
  (`w`, noVNC / xterm.js, copied with OSC 52), SSH options (`ssh_user`,
  `ssh_key`, `ssh_jump`, `ssh_options`).
- Auto-refresh countdown in the footer, `F6` pauses it.
- **Non-interactive commands**: `pvetty nodes|guests|tasks|storage|api ...`
  with JSON or table output (docs/CLI.md).
- **Plugins** (`plugins` setting): community-scripts installer, Ansible
  inventory; `menu_extend` / `toolbar_extend` API.
- Development: git repository, `tools/lint.sh` (shellcheck) and pre-commit
  hook, record / replay API backend, golden tmux screen tests
  (`tools/screen-test.sh`), Debian package (`tools/make-deb.sh`),
  AGENTS.md / CLAUDE.md, integration section `features`.

## 1.0.0 — 2026-10-06

First release.

- Text console version of the Proxmox VE 9 web interface (port 8006): header,
  resource tree (Server / Folder / Pool / Storage views), per-object menus,
  toolbars, panel button bars, Tasks / Cluster log panel, footer hints.
- Every menu of the web UI for Datacenter, Node, VM, Container, Storage,
  Pool and SDN zone, checked against the menu definitions of the installed
  web interface.
- Read and write: Add / Edit / Remove on every configuration table, dialogs
  generated from the API schema (property strings in sub-forms, typed objects
  restricted to the options of their type).
- Ceph (installation wizard, monitors, managers, OSD, CephFS, MDS, pools,
  flags, configuration, log), ACME (accounts, DNS / standalone plugins,
  domains, order / renew / revoke, custom certificates), storage creation of
  every type, disks (GPT, wipe, LVM, LVM-Thin, Directory, ZFS).
- Task viewer: opens when a task starts, follows its output live, Stop, stays
  open at the end, refreshes the panels when closed.
- Consoles: `qm terminal` (serial), SSH for Linux VMs without serial port
  (guest agent, neighbour table, network scan), `pct enter`, node shell.
- Braille RRD graphs, gauges, animated spinners; Nerd Font / Unicode / ASCII
  icons (with preview); default / dark / light / basic themes; keyboard
  (F1–F4 header buttons) and mouse.
- Persistent API helper (≈5 ms per read instead of 1–2 s with pvesh).
- i18n ready (English; template with 975 strings).
- Tools: `selftest.sh`, `integration-test.sh` (703 checks passed on PVE
  9.2.21), `i18n-extract.sh`, `install.sh`.
