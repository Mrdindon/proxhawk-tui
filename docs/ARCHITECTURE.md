# proxhawk-tui — Architecture

## Goals

- Look and behave like the Proxmox VE web interface.
- Smallest possible footprint: only what a Proxmox VE node already has
  (bash, Perl and the PVE Perl modules, `pvesh`, `whiptail`, `less`).
- Modular: adding a panel is adding a function; themes, icon sets and
  languages are data files.

## Modules

```
proxhawk-tui                main: options, initialisation, event loop, keys, mouse
lib/core.sh           configuration (CFG), run directory, logging, cleanup hooks
lib/term.sh           terminal setup (tput + ANSI fallbacks), key/mouse decoding
lib/theme.sh          loads themes/<name>.sh and compiles colours into C[...]
lib/glyphs.sh         icon / box drawing sets (G[...]), spinner frames
lib/i18n.sh           T / Tf translation helpers, language choice and loading
lib/i18n-pve.pl       translations from the Proxmox VE web interface catalog (pve-i18n)
lib/widgets.sh        formatting, ANSI-aware fit/strip, bars, braille charts, spinner
lib/api.sh            API access: broker co-process, pvesh fallback, background jobs
lib/user.sh           Proxmox VE user to run as (prompt, permissions, pvesh wrapper)
lib/pvesh-as.pl       pvesh as another user, with the API server permission check
lib/broker.pl         persistent read-only API helper (Perl)
lib/content.sh        content model (C_LINES...), tables, key/value lists
lib/resources.sh      /cluster/resources model (R_*), tree building (4 views)
lib/views.sh          view registry: context, menus, toolbars, content loading
lib/rrd.sh            RRD graphs (rrddata) in one or two columns
lib/tasks.sh          Tasks / Cluster log panel, task descriptions, log viewer
lib/dialog.sh         dialog / whiptail / built-in prompts
lib/form.sh           edit dialogs generated from the API schema
lib/crud.sh           Add / Edit / Remove declarations of the table panels
lib/choices.sh        value lists offered by the forms (disks, storages, users...)
lib/actions.sh        actions and toolbars (power, console, SSH, clone, wizards...)
lib/layout.sh         geometry and drawing of the whole screen
lib/taskviewer.sh     task viewer window (log / status of a running task)
lib/keys.sh           configurable global key bindings (KEYMAP, key.<action>)
lib/overlay.sh        scrollable window over the interface, help window
lib/queue.sh          per-guest action queue, batch actions on marked guests
lib/plugins.sh        optional plugins (plugins/*.sh), menu / toolbar extension
lib/onboarding.sh     first run wizard
lib/cli.sh            non-interactive subcommands (JSON / table output)
plugins/*.sh          bundled plugins (community-scripts, ansible-inventory)
views/*.sh            panels per object type: datacenter, cluster, access, acme, ceph,
                      firewall, sdn, node, guest, qemu, lxc, storage
themes/*.sh           colour themes
lang/*.sh             languages (strings of proxhawk-tui; lib/i18n-pve.pl adds the Proxmox VE GUI catalog)
tools/selftest.sh     renders every panel without UI and reports errors / timings
tools/integration-test.sh  read/write tests of every panel (see TESTING.md)
tools/i18n-extract.sh builds a translation template from the sources
tools/i18n-check.sh   translation coverage and placeholder check per language
tools/screen-test.sh  golden screen tests in tmux on recorded API answers
tools/lint.sh         bash -n, perl -c, shellcheck
tools/make-release.sh, tools/make-deb.sh   release archive, Debian package
```

Modules only define functions and global arrays; the order of loading is
fixed in `proxhawk-tui`. View modules are sourced automatically (`views/*.sh`).

## Data flow

```
             ┌──────────── read (GET) ─────────────┐
 views ──► api_get ──► broker.pl (co-process) ──► PVE::API2 handlers (local)
                │             └──► pvesh (remote node, SSH proxy)
                └──► pvesh get ... | broker.pl --filter   (fallback backend)

 actions ──► api_exec ──► setsid pvesh create|set|delete ... &   (background job)
          └► api_exec_sync ──► pvesh ... (with spinner)
```

### Record and replay

With `PROXHAWK_TUI_RECORD=DIR`, every answer of `api_get` (rows or error) is
saved in DIR under the MD5 of its request key (`mode|path|query|fields`),
with an `index` file and the node name. `backend = replay` with
`PROXHAWK_TUI_REPLAY=DIR` serves these files instead of the API and turns writes
into no-ops; `PROXHAWK_TUI_NOW` freezes the clock. The screen tests use it.

### The broker

`pvesh` loads the whole API stack at every call (≈1–2 s). `lib/broker.pl` loads
it once, then serves GET requests over stdin/stdout as a bash co-process
(`coproc BROKER`). It uses the same calls as `pvesh`
(`PVE::RPCEnvironment->setup_default_cli_env`, `PVE::API2->find_handler`,
`handle`) and refreshes the cluster file system state
(`PVE::Cluster::cfs_update`) before each request. Requests that must be
proxied to another cluster node are delegated to `pvesh`, which tunnels through
SSH exactly as usual.

Before each request the broker calls `init_request()` like `pvedaemon`
(refreshes the cluster file system state and the cached user configuration,
which pools and ACL listings depend on).

The broker is **read-only** (except the `write` fallback above): writes go
through `pvesh`, so the permission checks, task workers and logs are those of
the official tooling.

## Forms and CRUD

`form_run TITLE METHOD PATH` (lib/form.sh) asks the broker for the parameter
definitions of the call and builds a menu-driven form; the values of the
object are read from `FORM_GET`. Fields are edited with the widget matching
their type (Yes/No/Default, enumeration, list from `lib/choices.sh`, password,
input box, or a sub-form for property strings). On submit:

- POST: every non-empty value is sent;
- PUT: changed values are sent, emptied values go to `--delete`; parameters
  required by the call and arrays are always sent; calls without a `delete`
  parameter replace the whole object, so all their current values are sent;
- DELETE (e.g. prune backups): the values are sent as parameters.

`crud VIEW key=value...` (lib/crud.sh) declares the Add / Edit / Remove calls
of a table panel; panels holding several kinds of objects declare one
definition per kind (`crud VIEW:kind ...`) and prefix their row keys with
`kind|`. Typed objects (storage, realm, SDN...) first ask for the type and
restrict the form to the options of that type (`pluginopts`).

## Tasks

`pvesh` returns as soon as a worker task is started (it prints its UPID). The
UPIDs are followed (`TASK_WATCH`, polled by the main loop): the footer reports
the real exit status of the task when it stops. `API_WAIT_TASKS=1` (tests)
makes `api_exec_sync` wait for the task.

If the broker cannot start or dies, `api_get` switches to the `pvesh` backend
transparently (`backend = pvesh` forces it).

#### Protocol

Request — one line, TAB separated:

```
MODE <TAB> PATH <TAB> QUERY <TAB> FIELDS
```

| Part | Description |
|------|-------------|
| `MODE` | `rows` (TSV rows of FIELDS), `kv` (flattened `key<TAB>value`), `json`; `schema`, `propparse`, `propprint`, `pluginopts`, `write` (see below) |
| `PATH` | API path, e.g. `/nodes/pve1/qemu/100/status/current` |
| `QUERY` | URL-encoded parameters, `timeframe=hour&cf=AVERAGE` |
| `FIELDS` | comma separated field specifications (rows mode) |

Field specifications:

| Spec | Result |
|------|--------|
| `name` | value (arrays joined with `,`, objects as JSON) |
| `a.b.c` | nested value |
| `name*N` | number × N rounded to an integer (bash has integers only: `cpu*10000`) |
| `name:i` | number rounded to an integer |
| `name#` | number of elements of an array / hash |
| `@a.*.b;f1,f2` | prefix: select nested rows first (`*` = every array element) |

Response: data lines, then a terminator line `\x04OK` or `\x04ERR<TAB>message`.
Inside values, TAB becomes a space and newlines become `\x1f`.

Schema requests (used by the forms):

| Mode | Request | Result |
|------|---------|--------|
| `schema` | `PATH`, `method=POST\|PUT\|DELETE` | one row per parameter: name, type, optional, default, enum, type text, description, kind (`propstr`, `array`, `list`), min, max, password, default key. Path parameters are excluded; `allOf`/`oneOf` variants (HA rules) are merged |
| `schema` | ... `&param=net0` | the sub-options of a property string parameter |
| `propparse` | `param=net0&value=...` | `key<TAB>value` of a property string |
| `propprint` | `param=net0&k=v...` | the canonical property string |
| `pluginopts` | family (`storage`, `realm`, `sdnzone`, `sdncontroller`, `sdnipam`, `sdndns`, `metric`, `harule`), `type=` | options of that type (optional, fixed) and the list of types |
| `write` | `method=...&k=v...` | executes a non-task call with the parameters converted to their JSON types (fallback for endpoints that refuse the strings sent by `pvesh`, e.g. SDN prefix lists) |

`broker.pl --once MODE PATH QUERY FIELDS` answers one request (used by the
`pvesh` backend for the schema modes). `broker.pl --filter MODE FIELDS`
applies the same formatting to JSON read
from stdin; it is used by the `pvesh` backend so that views never depend on
the backend.

## Rendering

- The screen is fully redrawn into one string (`FRAME`) and written with a
  single `printf`, which avoids flickering. A frame costs ~30 ms on a low-end
  CPU.
- Widths are computed on visible characters: `strip` removes SGR sequences
  segment by segment (much faster than an extglob substitution) and `fit`
  pads/truncates ANSI strings.
- Glyph sets only contain single-cell characters, so `${#string}` is the
  display width.
- Content handlers produce pre-formatted lines (`C_LINES`) once per load; the
  layout only slices and highlights them, so scrolling is cheap.
- Braille charts: every character cell holds 2×4 dots; each data column is
  resampled to dot columns (peak value), filled from the bottom; a second
  series is coloured where it exceeds the first one.

## Event loop

```
draw → read_key (timeout) ─┬─ key / mouse → handle_key → (redraw)
                           └─ timeout ─┬─ debounced tree/menu selection → content_load
                                       ├─ api_jobs_poll (finished background jobs)
                                       └─ periodic refresh (resources, tasks, live panels)
```

- Moving in the tree or the menu is *debounced* (150 ms): keeping an arrow key
  pressed does not load every intermediate panel. Any non-navigation key
  applies the pending selection first, so actions always target the entry
  under the cursor.
- `SIGWINCH` recomputes the layout; `INT`/`TERM`/`HUP` stop the loop; the
  `EXIT` trap restores the terminal, stops the broker and removes the run
  directory.
- Dialogs, shells, consoles, editors and pagers run outside the full-screen
  mode (`term_run`), then the screen is redrawn.

## Security notes

- proxhawk-tui runs as root and uses the local API as `root@pam`, like `pvesh`. It
  does not open any port, store credentials or use the HTTP API.
- Writes are executed by `pvesh` with explicit arguments (no shell string
  evaluation of user input). Values typed in dialogs are passed as single
  arguments.
- Temporary files live in a private `mktemp -d` directory removed on exit.

## Testing

```bash
tools/selftest.sh                 # every panel of one resource per type
tools/selftest.sh qemu/100 lxc/101
```

It prints the rendering time and number of lines of each panel and fails if a
panel writes to stderr. The read/write tests (`tools/integration-test.sh`)
are described in [TESTING.md](TESTING.md).
