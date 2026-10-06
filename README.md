# pvetty — a text console for Proxmox VE

Version 1.3.0 · licence AGPL-3.0-or-later

`pvetty` is a text console version of the Proxmox VE web interface (the GUI
served on port 8006). It reproduces the layout, the navigation and most panels
of the web UI with Unicode box drawing, braille charts, Nerd Font icons and
ANSI colours, and needs nothing that is not already installed on a Proxmox VE
node.

![pvetty demo: datacenter, node and VM summaries, help window, tree views](docs/demo.gif)

*Demo data, 44 s — also as [MP4 video](docs/demo.mp4). Made with `tools/demo-video.sh`.*

## Highlights

- **Same layout and menus as the web UI** (checked against the menu definitions
  of Proxmox VE 9): header bar, resource tree (Server / Folder / Pool / Storage
  view), per-object navigation menu, toolbar, content panel and the
  *Tasks / Cluster log* panel.
- **Read and write**: every configuration table has *Add / Edit / Remove*
  (`a` / `e` / `d`). The dialogs are **generated from the API schema** of
  the call they perform, so they offer the same parameters, choices and
  defaults as the web UI dialogs, including property strings (`net0`,
  `scsi0`, `rootfs`...) edited in sub-forms.
- **Everything of the GUI**: Datacenter (cluster, options, storage of every
  type, backup jobs, replication, permissions, users, API tokens, TFA,
  groups, pools, roles, realms, HA and affinity rules, SDN with zones, VNets,
  subnets, controllers, IPAM, DNS, VNet firewall, fabrics, route maps, prefix
  lists, ACME, firewall, metric servers, resource and directory mappings,
  custom CPU models, notifications), Node (network with apply/revert,
  certificates and ACME orders, DNS, hosts, time, services, updates,
  repositories, disks with GPT/wipe, LVM, LVM-Thin, Directory, ZFS, **Ceph**
  with installation wizard, monitors, OSDs, CephFS, pools), VMs and containers
  (hardware/resources, cloud-init, options, snapshots, backups, restore,
  firewall, permissions, HA, clone, template, migrate).
- **Console**: `qm terminal` for VMs with a serial port, **SSH for Linux VMs
  without serial port** (IP found through the guest agent, the neighbour table
  or a scan of the bridge network), `pct enter` for containers, node shell.
- **Tiny footprint**: pure bash + the Perl and `pvesh` that ship with Proxmox
  VE. `whiptail` (also shipped) or `dialog` for dialogs. No daemon, no package
  to install, nothing written outside `~/.config/pvetty` and a temp directory.
- **Fast**: a small persistent Perl helper loads the API once and answers
  requests in milliseconds instead of spawning `pvesh` (1–2 s) for every read.
- **Tested**: `tools/integration-test.sh` drives every panel and action against
  a real node and verifies each write through the API (see
  [docs/TESTING.md](docs/TESTING.md)).
- **Modular**: every panel is a small function in `views/`; themes, icon sets
  and languages are plain files.
- **Keyboard and mouse**, 256 colours, truecolor or 8 colours, Nerd Font,
  Unicode, pure ASCII or no icons, multi-language ready (English included).
  Key bindings and colours are configurable; ten themes (Dracula, Nord,
  Gruvbox, Catppuccin, Tokyo Night...).
- **Batch actions and queue**: mark guests with `Space` in the search grids,
  start / stop / back them up together; actions on a busy guest are queued.
- **Scriptable**: `pvetty guests list -o table`, `pvetty guests start 101`,
  `pvetty api get /version`... (JSON or table output, see
  [docs/CLI.md](docs/CLI.md)).
- **Plugins**: optional menu entries (community-scripts installer, Ansible
  inventory) — see [docs/EXTENDING.md](docs/EXTENDING.md#plugins).

## Requirements

| Component | Notes |
|-----------|-------|
| Proxmox VE 7, 8 or 9 node | run as `root` (already authenticated as `root@pam`) |
| bash ≥ 4.3 | standard |
| perl + PVE Perl modules | shipped with Proxmox VE |
| `whiptail` or `dialog` | `whiptail` is installed by default; built-in prompts otherwise |
| `less` | optional, used to display logs |
| A UTF-8 terminal, ≥ 80×18 | 256 colours recommended; a Nerd Font for the original icons |

## Install

On a Proxmox VE node, as root, one line installs the latest release (the
`.deb` is checked against its SHA-256 before `apt` installs it):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Mrdindon/pvetty/main/install.sh)"
pvetty
```

Update: run the same line again. Remove: `apt remove pvetty`. You can read
[install.sh](install.sh) before running it; the packages are also on the
[releases page](https://github.com/Mrdindon/pvetty/releases).

From the sources:

```bash
git clone https://github.com/Mrdindon/pvetty.git && cd pvetty
./pvetty                      # run in place
./install.sh                  # or: symlink /usr/local/bin/pvetty
```

Useful options:

```bash
pvetty --glyphs nerd          # Font Awesome icons of the web UI (needs a Nerd Font in YOUR terminal,
                              # see docs/CONFIGURATION.md)
pvetty --theme dark           # painted "Proxmox Dark" look
pvetty --select qemu/100      # open directly on VM 100
pvetty --backend pvesh        # do not use the persistent API helper
```

## Essential keys

| Key | Action |
|-----|--------|
| `↑` `↓` / `j` `k`, `PgUp` `PgDn`, `Home` `End` | move in the focused panel |
| `Tab` / `Shift+Tab` | next / previous panel (tree → menu → content → tasks) |
| `←` `→` | collapse / expand in the tree, move between panels |
| `Enter` | open / act on the selected row |
| `/` | search resources |
| `v` | cycle the tree view (Server, Folder, Pool, Storage) |
| `a` `e` `d` | Add, Edit, Remove in configuration tables |
| `s` `h` `c` `H` `m` | Start, Shutdown menu, Console, SSH, More (guests) |
| `b` `h` `S` `B` | Reboot, Shutdown, Shell, Bulk Actions (nodes) |
| `t` | change the graph timeframe in summaries |
| `l` | switch *Tasks* / *Cluster log* |
| `r` / `F5` | refresh |
| `F1` / `?` | help window: keys of the current panel |
| `F2` `F3` `F4` | header buttons: Create VM, Create CT, user menu (settings, icons, language...) |
| `Space` `m` `f` | mark a guest, batch actions, filter (search grids) |
| `w` | browser console URL (noVNC / xterm.js) of a guest or node |
| `F6` | pause / resume the automatic refresh |
| `q` / `F10` | quit |

The full list is in [docs/USAGE.md](docs/USAGE.md).

## Documentation

| Document | Content |
|----------|---------|
| [docs/USAGE.md](docs/USAGE.md) | user guide: screen layout, navigation, every panel and action |
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | configuration file, key bindings, colours, command line, plugins, themes, icon sets |
| [docs/CLI.md](docs/CLI.md) | non-interactive commands (JSON / table) |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | modules, data flow, API broker protocol, rendering |
| [docs/EXTENDING.md](docs/EXTENDING.md) | how to add a panel, an action, a theme or an icon set |
| [docs/I18N.md](docs/I18N.md) | translations and adding a language |
| [docs/TESTING.md](docs/TESTING.md) | lint, self test, golden screen tests, read/write integration tests |
| [AGENTS.md](AGENTS.md) | short guide for coding agents |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | internal notes: design decisions, Proxmox VE behaviours, release procedure |
| [CHANGELOG.md](CHANGELOG.md) | versions |
| [docs/COMPARISON-devnullvoid-pvetui.md](docs/COMPARISON-devnullvoid-pvetui.md) | analysis of devnullvoid/pvetui and improvement ideas |

## Project layout

```
pvetty              entry point (argument parsing, main loop, key/mouse handling)
install.sh          install / uninstall a symlink in /usr/local/bin
lib/                core modules (terminal, API, widgets, layout, actions...)
lib/broker.pl       persistent read-only API helper (Perl, PVE modules)
views/              one file per object type (datacenter, node, qemu, lxc...)
themes/             colour themes
plugins/            optional plugins (enabled in F4 > Plugins)
tests/screens/      screen test scenarios, recorded API answers, golden screens
lang/               language files (en.sh + TEMPLATE.sh)
conf/               example configuration
tools/              lint.sh, selftest.sh (render every panel), screen-test.sh,
                    integration-test.sh + integration/*.sh (read/write tests),
                    i18n-extract.sh, make-release.sh, make-deb.sh
docs/               documentation
```

## Limitations

- The graphical consoles (noVNC, SPICE) cannot be displayed in a terminal:
  serial console, SSH or `pct enter` are used instead (`w` gives the browser
  URL of the noVNC console).
- Runs on a node of the cluster only (no remote API connection yet).
- The interface is meant to run as `root` on a cluster node: it uses the local
  API stack directly (no HTTP, no ticket), exactly like `pvesh`.
- Uploads (ISO, templates, snippets) take a file of the node itself.

## How it was made

pvetty was written with [Claude Code](https://claude.com/claude-code),
Anthropic's AI coding agent, directed and reviewed by the author and
tested on a real Proxmox VE node (see [docs/TESTING.md](docs/TESTING.md)).
The design notes and lessons learned are in
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md); [AGENTS.md](AGENTS.md) is the
guide given to coding agents working on it.

## Licence and name

pvetty is free software under the **GNU Affero General Public License v3.0
or later** (see [LICENSE](LICENSE)), the licence of Proxmox VE itself, whose
Perl modules the API helper loads.

Proxmox® is a registered trademark of Proxmox Server Solutions GmbH. pvetty
is an independent project, not affiliated with or endorsed by Proxmox
Server Solutions GmbH. It was called *pvetui* before 1.2.0 (renamed because
of an unrelated project with that name).
