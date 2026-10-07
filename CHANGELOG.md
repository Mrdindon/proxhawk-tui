# Changelog

## Unreleased

- **Languages**: French, Spanish, German, Chinese (simplified) and Russian
  (about 93 %; the rest are names such as ZFS or SPICE). The official message
  catalog of the Proxmox VE web interface installed on the node is used at
  run time: the same words as the GUI, and 34 languages available (12 to 51 %
  for the languages without a pvetty file).
- `language = auto`: the locale when it is not English, else the datacenter
  language (Datacenter › Options › Language), else English.
- Double width characters (Chinese, Japanese, Korean) are laid out correctly.
- `tools/i18n-check.sh` (coverage, placeholder check); the extractor splits
  key hints into labels and ignores technical strings; screen tests in other
  languages (`name@code`).

## 1.3.1 — 2026-10-06

- The start-up question "run as which user" is now always asked (unless
  `ask_user = 0`, `--user` or `user = ...`): it was skipped when root@pam
  was the only Proxmox VE user. "Other user" accepts any user ID; an
  unknown or disabled user shows a message and asks again.
- **PAM users**: when the Linux account does not exist, pvetty offers to
  create it if the user it runs as may create Linux accounts (a pam user
  that is root or may run `useradd` with sudo); the account is created
  through that user's sudo, after checking `Realm.AllocateUser`.
- **Demo**: the README GIF shows Datacenter Summary and HA, Node Summary,
  Network, System Log, Community Scripts and Disks, VM Summary and Options,
  on fictional data; the MP4 version is removed. The demo tooling is no
  longer part of the repository. The Community Scripts plugin works on
  recorded API answers (replay backend).
- **Ansible inventory plugin**: `s` wrote nothing ("Cannot write": the file
  name was lost before writing); it now creates the folders, asks before
  replacing a file and reports the hosts written. The inventory lines are
  selectable (a cursor shows the position when scrolling), `v` opens it in
  the pager, and guests with the same name no longer produce a duplicate
  YAML key.
- **Fix** (running as another user): writes were refused for every user
  other than root@pam, even with the right permissions (the pvesh wrapper
  checked pvesh's own command instead of the API method). Methods open to
  everyone (realm list) are no longer refused.

## 1.3.0 — 2026-10-06

- **Run as another Proxmox VE user**: at start-up pvetty asks which user to
  run as (`ask_user`), or takes `--user` / `user = ...` (also for the CLI
  subcommands). The user's permissions apply like in the web UI: API calls
  checked with `check_api2_permissions`, filtered lists, tasks logged under
  the user, consoles need `VM.Console` / `Sys.Console`.
- **One-line install**: `bash -c "$(curl -fsSL
  https://raw.githubusercontent.com/Mrdindon/pvetty/main/install.sh)"`
  installs the latest `.deb` (checked with its SHA-256); `--uninstall`.
- **Fix**: adding a user failed with "change password failed: user 'test'
  does not exist" (the API wants `name@realm`). Add now asks the realm and
  the name like the web UI; the password is only set for the pve realm.
- The README says that pvetty is developed with Claude Code.

## 1.2.1 — 2026-10-06

- **Fix**: pvetty kept running at full CPU after its terminal was closed
  (SSH disconnect, killed tmux session) or on SIGTERM while a dialog or the
  help window was open. It now exits and cleans up.
- **Plugins dialog**: a checklist (`Space` ticks, `Enter` validates; `Enter`
  on Ok toggled a plugin again) and an offer to restart pvetty, keeping the
  current selection.
- **Dialogs**: action menus name their buttons (Settings: Change / Close,
  forms: Select / Cancel); menus fit the width of their longest line;
  message, question and input boxes take the size of their text (long
  errors were cut).
- **Demo** in the README (GIF and MP4), made from a storyboard on demo data
  with `tools/demo-video.sh` and `tools/render-video.py`.

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
