# pvetty — User guide

This guide follows the structure of the Proxmox VE web interface
(<https://pve.proxmox.com/pve-docs/chapter-pve-gui.html>): if you know the web
UI you already know where everything is.

## 1. Starting

```bash
pvetty [options]
```

`pvetty` must run as `root` on a Proxmox VE node. There is no login: the
session is the local `root@pam` user, as with `pvesh`. pvetty first asks
which Proxmox VE user to run as (the launching user or another one): that
user's permissions then apply, as in the web UI (see
[CONFIGURATION.md](CONFIGURATION.md#running-as-another-user)). See
[CONFIGURATION.md](CONFIGURATION.md) for all options.

At start-up the API helper is loaded (1–2 seconds, a spinner is shown in the
footer), then the Datacenter is selected (setting `startup`: `last` restores
the selection of the previous session, or give a tree id such as `qemu/100`).

The first time (no user configuration file), a short wizard asks for the
icon set (with a preview), the theme and the mouse support. It can be run
again with `F4` › Settings, or disabled with `onboarding = 0`.

`pvetty <command>` runs a non-interactive command instead of the interface
(`pvetty guests list`, `pvetty api get /version`...): see [CLI.md](CLI.md).

## 2. Screen layout

```
┌ Header ────────────────────────────────────────────────────────────────────────┐
│ PROXMOX Virtual Environment x.y   ⌕ Search   ? Documentation  ▭ Create VM ... │
├ Resource tree ─────┬ Content panel ────────────────────────────────────────────┤
│ ▾ ▦ Datacenter     │ Title ........................... [Start] [Shutdown] ... │
│   ▾ ▣ node1        ├ Menu ────────────┬ Content ───────────────────────────────┤
│       ▭ 100 (vm)   │ ≣ Summary        │                                        │
│       ◈ 101 (ct)   │ ▭ Hardware       │                                        │
│       ◫ local      │ ...              │                                        │
├ Tasks │ Cluster log ┴──────────────────┴────────────────────────────────────────┤
│ Start Time   End Time   Node   User name   Description                Status   │
└ Footer: key hints, status messages ────────────────────────────────────────────┘
```

| Area | Web UI equivalent | Content |
|------|-------------------|---------|
| Header | top bar | logo, version, Search (`/`), Documentation (`F1`), Create VM (`F2`), Create CT (`F3`), user menu (`F4`); the keys are shown in the buttons |
| Resource tree | left tree | Datacenter, nodes, guests, SDN zones, storages, pools |
| Title + toolbar | panel header | object name, tags, lock, buttons (Start, Shutdown, Console, More...) |
| Menu | left column of the panel | panels of the selected object (Summary, Hardware...) |
| Content | panel body | tables, key/value lists, gauges, graphs, logs |
| Tasks / Cluster log | bottom log panel | recent tasks of the cluster, or the cluster log |
| Footer | — | key hints of the focused panel, results of actions, running jobs |

The focused panel has its selection highlighted in blue; other panels show
their selection in grey.

### Tree icons and colours

| Unicode | Nerd Font | ASCII | Object |
|---------|-----------|-------|--------|
| ▦ | `` | D | Datacenter |
| ▣ | `` | N | node (green = online, red = offline) |
| ▭ | `` | V | virtual machine (green = running, grey = stopped, yellow = paused) |
| ◈ | `` | C | container |
| ▯ | `` | T | template |
| ◫ | `` | S | storage (red = not available) |
| ⌗ | `` | Z | SDN zone |
| ◇ | `` | P | pool |
| ⊘ | `` | L | lock (backup, migrate, snapshot...) |

Guest tags are displayed after the name (`show_tags` option).

### Tree views

Press `v` (or click the view title) to cycle like the web UI selector:

- **Server View** — Datacenter › nodes › guests, SDN zones, storages
- **Folder View** — Datacenter › LXC Container / Nodes / Pools / SDN / Storage / Virtual Machine
- **Pool View** — Datacenter › pools › members
- **Storage View** — Datacenter › nodes › storages

## 3. Navigation

### Keyboard

| Key | Tree | Menu | Content | Tasks |
|-----|------|------|---------|-------|
| `↑` `↓` `j` `k` | move (selects after a short pause) | change panel | move row / scroll | move |
| `PgUp` `PgDn` | page | page | page | page |
| `Home` `End` `g` `G` | first / last | first / last | first / last | first / last |
| `←` | collapse, then go to parent | focus tree | focus menu | — |
| `→` | expand, then focus menu | focus content | — | — |
| `Space` | collapse / expand | — | — | — |
| `Enter` | focus menu | focus content | open / act on row | show task log |
| `Esc` | — | focus tree | focus tree | focus tree |

Global keys:

| Key | Action |
|-----|--------|
| `Tab` / `Shift+Tab` | next / previous panel |
| `/` | search (filter of the Datacenter › Search grid) |
| `v` | cycle tree view |
| `l` | switch the bottom panel between *Tasks* and *Cluster log* |
| `r`, `F5` | refresh everything (data cache is cleared) |
| `F6` | pause / resume the automatic refresh |
| `F1`, `?` | header button **Documentation**: help window with the keys of the current panel (toolbar, panel buttons, global keys); `d` opens this guide |
| `F7` | this guide |
| `F2` (or `V`) | header button **Create VM** (wizard) |
| `F3` (or `C`) | header button **Create CT** (wizard) |
| `F4` (or `U`) | header button **root@pam ▾**: *Application Settings* (language, icons with preview, theme, mouse, confirmations, refresh, start-up selection, IP column, SSH, plugins, key bindings, about) and quit |
| `q`, `F10` | quit (asks first when actions started by pvetty are still running or queued) |

These keys can be changed in the configuration file (`key.<action>`, see
[CONFIGURATION.md](CONFIGURATION.md#key-bindings)).

The letters `V`, `C` and `U` are only shortcuts when the panel does not use
them itself (e.g. `C` creates a cluster in Datacenter › Cluster): the function
keys always work. Toolbar keys are shown underlined in the buttons (letters are case
insensitive in the label, e.g. **S**tart is `s`); disabled buttons are dimmed.

### Mouse

With `mouse = 1` (default):

- click a tree entry, a menu entry, a table row, a task;
- click the expander (`▾`/`▸`) to collapse / expand;
- double-click a row = `Enter`;
- click toolbar buttons and header buttons;
- click the tree title to change the view, the bottom panel title to switch
  Tasks / Cluster log;
- mouse wheel scrolls the panel under the pointer.

Hold `Shift` while selecting text to copy it (terminal feature).

### Automatic refresh

Every `refresh` seconds (default 5) the resource tree, the task list and the
"live" panels (summaries, task histories, system log, search grids) are
reloaded. The selection and the cursor position are kept. The footer shows
the time left before the next refresh (`↻ 3s`); `F6` pauses it.

## 4. Panels

The menus are the same as the web UI of Proxmox VE 9 (they were checked
against the menu definitions of the installed web interface).

### Editing: Add / Edit / Remove

Every table that can be changed in the web UI shows a button line at the top
of the panel and accepts the same keys:

| Key | Action |
|-----|--------|
| `a` / `Insert` | **Add** (when a panel holds several kinds of objects, a menu asks which one, e.g. *Account* or *Challenge Plugin*) |
| `e` / `Enter` | **Edit** the selected row |
| `d` / `Delete` | **Remove** the selected row (with confirmation) |

Every panel with actions shows them in a **button bar** pinned above its
content, like the toolbars of the web UI panels (e.g. Updates:
`Refresh R  Upgrade u  Changelog ⏎`). Each button shows its key; it can be
clicked with the mouse, or its key pressed while the content panel has the
focus (`Tab` or `→` to reach it). The same keys are listed in the footer.

#### Adding a user

`a` in Datacenter › Users asks the realm, then the user name (without
`@realm`), then the other fields, like the web UI. The password is set for
the `pve` and `pam` realms (for `pam` it is the Linux password); LDAP / AD /
OpenID users authenticate on their server.

A `pam` user needs a Linux account on the node. When it does not exist,
pvetty offers to create it (`useradd -m -s /bin/bash`) only if the user
pvetty runs as may create Linux accounts itself: a `pam` user whose Linux
account is root or may run `useradd` with sudo (checked with `sudo -l`).
The account is then created through that account (`runuser` + `sudo`:
its sudo rules apply, sudo may ask its password and logs the action), and
the Proxmox VE right to add `pam` users (`Realm.AllocateUser` on
`/access/realm/pam`) is checked first. Otherwise pvetty explains how to
create the account. On a cluster, create the account on the other nodes
too.

#### Forms

Add and edit dialogs are generated from the API definition of the call they
perform (the same parameters, types, allowed values and defaults as the web
UI dialogs):

```
┌──────────────── Add: Network Device: Linux Bridge ────────────────┐
│ Select a field to change it, then OK.  * = required               │
│                 ✔ Create                                          │
│                 Interface *                vmbr2                  │
│                 CIDR                       10.10.0.1/24           │
│                 Autostart                  (Default: 1)           │
│                 Bridge ports                                      │
│                 VLAN aware                                        │
│                 Comment                                           │
│                 ▸ Advanced (4 more options)                       │
└───────────────────────────────────────────────────────────────────┘
```

- select a field and press `Enter` to change it: Yes/No/Default menu for
  booleans, a list for enumerations or known values (storages, nodes, users,
  unused disks, bridges, time zones...), an input box otherwise (with the API
  description and format);
- *property strings* (e.g. `net0`, `scsi0`, `rootfs`, `acmedomain0`,
  `ipconfig0`, `agent`, `startup`) open a sub-form with one entry per option;
- `▸ Advanced` reveals the less common options;
- `✔ Create` / `✔ OK` sends the request; only changed values are sent and
  emptied values are removed (or not sent when the call replaces the whole
  object, e.g. the node DNS settings);
- errors returned by the API are displayed and the form stays open.

Typed objects (storage, realm, SDN zone, controller, IPAM, DNS, HA rule, metric
server, notification target, network device) first ask for the type and only
show the options of that type.

### Datacenter

| Panel | Content | Keys |
|-------|---------|------|
| Search | all resources | `Enter` go to resource, `Space` mark, `m` batch actions, `f` filter (see [Search grids](#search-grids)) |
| Summary | health, guests, resources, nodes | `Enter` go to node |
| Notes | datacenter notes | `e` edit in `$EDITOR` |
| Cluster | cluster information and nodes | `C` Create Cluster, `J` Join Information, `j` Join Cluster |
| Ceph | Ceph status | `F` global flags, `I` install, `N` initialize |
| Options | datacenter options (labels and defaults of the web UI) | `Enter` edit |
| Storage | storage definitions | `a` add (Directory, LVM, LVM-Thin, BTRFS, NFS, SMB/CIFS, GlusterFS, iSCSI, CephFS, RBD, ZFS, ZFS over iSCSI, PBS, ESXi), `e`, `d` |
| Backup | backup jobs | `a`, `e`, `d`, `R` run now, `J` job detail |
| Replication | replication jobs | `a`, `e`, `d` |
| Permissions | ACL | `a` add User / Group / API Token permission, `d` |
| Users | users | `a`, `e`, `d`, `p` password, `u` unlock TFA |
| API Tokens | tokens (the secret is displayed once) | `a`, `e`, `d` |
| Two Factor | TOTP, WebAuthn, recovery keys... | `a`, `e`, `d` |
| Groups, Pools, Roles | | `a`, `e`, `d` |
| Realms | PAM, PVE, AD, LDAP, OpenID | `a`, `e`, `d`, `s` sync |
| HA | status and resources | `a`, `e`, `d`, `M` migrate, `L` relocate, `A` arm, `D` disarm |
| HA › Affinity Rules | node / resource affinity rules | `a`, `e`, `d` |
| HA › Fencing | fencing information | |
| SDN | status | `A` apply, `X` rollback pending changes |
| SDN › Zones, VNets (with subnets), Options (controllers, IPAM, DNS), IPAM, VNet Firewall, Fabrics (with nodes), Route Maps, Prefix Lists (with entries) | pending changes are shown in a *State* column | `a`, `e`, `d`, `A`, `X` |
| ACME | accounts and challenge plugins | `a` register account (directory + terms of service) or add plugin (DNS provider list, credentials edited in `$EDITOR`), `e`, `d`, `Enter` details |
| Firewall, Options, Security Group (with rules), Alias, IPSet (with entries) | | `a`, `e`, `d`, `m` move rule |
| Metric Server | InfluxDB, Graphite, OpenTelemetry | `a`, `e`, `d` |
| Resource Mappings, Directory Mappings | PCI, USB, directories | `a`, `e`, `d` |
| Custom CPU Models | | `a`, `e`, `d` |
| Notifications | targets (Sendmail, SMTP, Gotify, Webhook) and matchers | `a`, `e`, `d`, `t` test target |
| Support | subscription | |

### Search grids

The grids listing resources (Datacenter › Search, Node › Search, folder
views, Pool › Summary) show the guest IP addresses (`ip_column`) and accept:

- `Space`: mark / unmark a guest (`✔` column);
- `m`: **batch actions** on the marked guests (or the guest of the row):
  Start, Shutdown, Stop, Reboot, Suspend, Resume, Backup now. They go
  through the action queue (below);
- `f`: **filter** by status, type, node and tag (values chosen in a list
  of the existing ones); the active filter is shown above the grid, and
  *Clear all filters* removes it. It is combined with the `/` search text.

### Node

| Panel | Content | Keys |
|-------|---------|------|
| Search, Summary, Notes, Shell | | `t` graph timeframe, `e` edit notes, `Enter` shell |
| System | services | `Enter` status, `S` start, `x` stop, `R` restart |
| Network | interfaces and pending changes (diff) | `a` (Linux Bridge/Bond/VLAN, OVS...), `e`, `d`, `A` apply configuration, `X` revert |
| Certificates | certificates and ACME domains | `u` upload custom, `D` delete custom, `a`/`e`/`d` ACME domains, `A` ACME account, `O` order, `R` renew, `V` revoke, `Enter` view |
| DNS, Hosts, Options, Time | | `Enter`/`e` edit (`/etc/hosts` in `$EDITOR`) |
| System Log | journal | scroll |
| Updates, Repositories | | `R` refresh, `u` upgrade, `Enter` changelog; `a` add standard repository, `e` enable/disable |
| Firewall, Options, Log | | `a`, `e`, `d`, `m` |
| Disks | disks and partitions | `Enter` S.M.A.R.T., `G` initialize GPT, `W` wipe (the device name must be typed) |
| LVM, LVM-Thin, Directory, ZFS | | `a` create (unused disks are offered), `d` destroy (with cleanup), `Enter` ZFS details |
| Ceph | status, or install / initialize wizard | `I`, `N`, `F` |
| Ceph › Configuration, Monitor, OSD, CephFS, Pools, Log | | monitors/managers/MDS: `a`, `d`, `S`/`x`/`R` start/stop/restart; OSD: `a` create, `d` destroy, `o`/`i` out/in, `s` scrub, `Enter` details; CephFS: `a`, `d`; Pools: `a`, `e`, `d` |
| Replication | | `N` schedule now, `L` log |
| Task History | | `Enter` log, `x` stop task |
| Subscription | | `u` upload key, `c` check, `d` remove key |

Toolbar: **Reboot** (`b`), **Shutdown** (`h`), **Shell** (`S`),
**Bulk Actions** (`B`).

### Virtual machine (QEMU)

| Panel | Keys |
|-------|------|
| Summary | `t` timeframe |
| Console | `Enter`: serial console (`qm terminal`), or SSH for Linux VMs without serial port |
| Hardware | `a` add (Hard Disk, CD/DVD Drive, Network Device, EFI Disk, TPM State, USB Device, PCI Device, Serial Port, CloudInit Drive, Audio Device, VirtIO RNG, Virtiofs), `e`/`Enter` edit (Memory and Processors dialogs group their options), `d` remove/detach, `R` resize disk, `m` move disk, `v` revert pending change |
| Cloud-Init | `e`/`Enter` edit, `R` regenerate image |
| Options | `e`/`Enter` edit, `d` reset to default |
| Task History | `Enter` log |
| Monitor | `Enter` type a command |
| Backup | `n` backup now, `r` restore, `Enter` restore / configuration / protection / notes / remove |
| Replication | `a`, `e`, `d` |
| Snapshots | `n` take, `R` rollback, `d` remove, `Enter` menu |
| Firewall, Options, Alias, IPSet, Log | `a`, `e`, `d`, `m` |
| Permissions | `a`, `d` |

Toolbar: **Start** (`s`), **Shutdown** (`h`: Shutdown, Stop, Reboot,
Pause/Resume, Hibernate, Reset), **Console** (`c`), **SSH** (`H`), **Web
console** (`w`), **More** (`m`: Clone, Convert to template, Migrate, Manage
HA, Edit Notes, Backup now, Take Snapshot, Run command, Browser console
(URL), Remove).

- **Web console** / **Browser console (URL)** builds the noVNC (VM) or
  xterm.js (CT, node shell) URL of the web UI, copies it to the clipboard of
  your terminal (OSC 52) and shows it as a clickable link. The host is the
  node IP, or `console_host`.
- **Run command** runs a shell command in the guest (QEMU guest agent for
  VMs, `pct exec` for containers) and shows its output and exit code.
- The guest title shows a spinner while a task runs on the guest.

#### Console and SSH

- With a serial port (`serial0`), **Console** opens `qm terminal` (exit with
  `Ctrl+O`).
- Linux VMs (OS type *Linux*) without serial port are offered an **SSH**
  connection instead. The IP address is taken from the QEMU guest agent, or
  from the neighbour (ARP) table of the node matched against the MAC addresses
  of the VM; if nothing is found, *Scan the bridge network* pings the subnet of
  the VM bridge (up to /24) and looks again. Any other address can be typed.
- Other VMs: add a serial port (`a` in Hardware › Serial Port).

### Container (LXC)

Same as virtual machines, with **Resources** (`a` add Mount Point / Device
Passthrough, `e`, `d`, `R` resize, `m` move volume), **Network** (`a`, `e`,
`d`), **DNS** and **Options**. **Console** runs `pct enter`.

### Storage

**Summary**, **Backups** (`r` restore, `e` notes / protection, `P` prune,
`d` remove, `Enter` show configuration), **ISO Images** / **CT Templates** /
**Import** (`U` upload a local file, `u` download from URL, `T` template list),
**Snippets** (`U` upload), **VM Disks**, **CT Volumes** (`d` remove unused),
**Permissions** (`a`, `d`).

### Pool and SDN zone

Pools: **Summary**, **Members** (`a` add VM or storage, `d` remove),
**Permissions**. SDN zones: **Content**, **IP-VRF**, **MAC-VRFs** (EVPN
zones), **Permissions**.

## 5. Tasks and actions

- Starting an action that runs a **task** (start, backup, migrate, disk
  creation, apt update...) opens the **Task viewer** over the interface, as in
  the web UI. It takes the focus and shows:
  - **Output**: the task log, followed live (`End` follows again after a
    manual scroll);
  - **Status**: status, exit status, node, user, start time, PID...;
  - the state (`⠹ running`, `✔ OK`, or the error) and the buttons
    **Stop** (`x`) and **Close** (`Esc`, `q`, `Enter`).

  Keys: `Tab` / `←` `→` switch Output / Status, `↑` `↓` `PgUp` `PgDn` `Home`
  `End` scroll. The mouse wheel and the buttons work too.
- The window stays open when the task ends. When it is closed, the panels
  behind it (tree, content, task list) are **refreshed**, and the result is
  shown in the footer. A task still running when the window is closed keeps
  being followed: the footer reports its result when it stops.
- Actions without a task (configuration changes) report their result in the
  footer.
- `Enter` (or a double-click) on a task of the *Tasks* panel or of a *Task
  History* opens it in the same viewer.
- Power actions ask for confirmation (`confirm` option). Removing a guest
  requires typing its ID, as in the web UI.
- **Action queue**: a guest runs one task at a time. An action on a guest
  that already runs a task (started here, in the web UI or by a job) can be
  **queued**: it starts automatically when the guest is free. Batch actions
  use the queue too, with at most `queue_parallel` actions at once. Queued
  actions appear in the *Tasks* panel (`queued`); `x` on a queued action
  cancels it, `x` on a running task stops it.
- Guests with a running task show a spinner in the tree.

## 6. Dialogs, editor and pager

- Dialogs use `dialog` if installed, otherwise `whiptail` (installed on every
  Proxmox VE node), otherwise simple prompts.
- Notes are edited with `$VISUAL`, `$EDITOR`, `nano` or `vi` (multi-line, like
  the web UI Markdown notes).
- Logs and long texts use `$PAGER` or `less -R`.

## 7. Troubleshooting

| Symptom | Fix |
|---------|-----|
| Squares or `?` instead of icons | use `--glyphs unicode` or install a Nerd Font for `--glyphs nerd` |
| Wrong colours / unreadable | `--theme basic` (8 colours) or `--theme light` on light terminals |
| "Terminal too small" | at least 80×18 is required |
| Very slow panels | check `--backend`: the broker should be used (`U` › About shows the backend) |
| Debug | `PVETTY_DEBUG=1 pvetty` writes a debug log to `/tmp/pvetty-debug.log` (or `$PVETTY_LOG`) |
