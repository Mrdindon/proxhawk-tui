# pvetty — Development notes (internal)

> pvetty is developed with Claude Code (Anthropic's AI coding agent),
> directed and reviewed by the author; AGENTS.md is the agents' entry point.

> Called *pvetui* until 1.1.0: the release archives 1.0.0 / 1.1.0, the git
> history use the old name.

Internal notes kept with the source: design decisions, Proxmox VE behaviours
found during development, lessons learned and the release procedure. User
documentation is in USAGE.md / CONFIGURATION.md; the code structure is in
ARCHITECTURE.md and EXTENDING.md.

## History

| Version | Date | Content |
|---------|------|---------|
| 1.2.1 | 2026-10-06 | exit when the terminal is closed (runaway CPU fix), plugins checklist and restart, dialog sizing and button labels, demo video |
| 1.2.0 | 2026-10-06 | renamed pvetui → pvetty (name clash, Proxmox trademark guidelines), AGPL-3.0-or-later licence, migration of the old user files |
| 1.1.0 | 2026-10-06 | help window, key bindings, colours/themes, settings screen, onboarding, action queue, batch actions, filter, IP column, run command, browser console URL, CLI subcommands, plugins, git + lint, replay backend, screen tests, .deb |
| 1.0.0 | 2026-10-06 | first release: read/write console for every menu of the PVE 9 web UI, schema-driven forms, task viewer, Ceph/ACME/storage/disks, SSH console for Linux VMs, integration tests (703 checks) |

Development node: Proxmox VE 9.2.21, single node with a low-power 4-core Intel CPU,
kernel 7.0.14-20-pve, two spare test disks (`/dev/sdb`, `/dev/sdc`).

## Design decisions

- **Footprint**: bash + what PVE already ships (Perl and the PVE modules,
  `pvesh`, `whiptail`, `less`). No package, no daemon, no Python. Rejected:
  `jq` (not installed by default), ncurses programs, the HTTP API (needs a
  ticket or token).
- **API helper (`lib/broker.pl`)**: `pvesh` costs 1–2 s per call on this CPU
  (it loads the whole API at every start). A persistent co-process loads it
  once (≈5 ms per request afterwards). It is read-only except the `write`
  fallback; writes go through `pvesh` for the official permission checks and
  task logs. It must call `init_request()` before each request, like
  `pvedaemon`, otherwise the cached user configuration (pools, ACL) is stale.
- **Forms from the API schema (`lib/form.sh`)**: instead of hand-writing ~100
  dialogs, the schema of each call (types, enums, defaults, descriptions,
  property strings) builds the form. This gives the same parameters as the
  web UI and follows future PVE versions. Hand-made parts are limited to
  labels (`FORM_LABELS_STD`), field order and value lists (`lib/choices.sh`).
- **CRUD declarations (`lib/crud.sh`)**: one line per table panel; multi-table
  panels use `crud view:kind` and row keys `kind|...`.
- **Rendering**: one string per frame, written at once (no flicker). ANSI
  stripping is segment based: the extglob substitution was 15× slower
  (≈500 ms per frame on a 4-core Intel CPU, now ≈35 ms).
- **Debounce** of the tree/menu selection (150 ms) and **flush before any
  action key**, so that an action never targets the previous selection.
- **Task viewer**: pvesh runs worker tasks synchronously in CLI mode (it
  returns when the task ends, `RESTEnvironment::fork_worker` with
  `type eq 'cli'`). Commands are therefore started in the background and the
  new task is detected in `/nodes/N/tasks?source=active` (1–3 s), then the
  viewer follows its log. The viewer stays open at the end and the panels are
  refreshed when it is closed (same as the web UI).
- **Single-cell glyphs only**: Nerd Font icons are Font Awesome code points
  (same icons as the web UI); emoji and CJK are avoided to keep `${#s}` equal
  to the display width.
- **i18n**: gettext-like, the English source string is the key; empty
  translations fall back to English.

## Proxmox VE behaviours to remember

| Behaviour | Handling |
|-----------|----------|
| `pvesh` worker tasks are synchronous in CLI mode | background start + detection in the active task list |
| PUT calls without a `delete` parameter replace the whole object (e.g. node DNS: omitting `dns1` removed it) | the form sends every current value for such calls |
| Some calls use a boolean `delete` (pools, ACL) | not treated as an option list |
| Arrays of property strings (mappings `map`) contain commas | the helper joins arrays with `\x1e` in `kv` mode |
| Rust backed SDN endpoints (prefix lists, route maps) refuse numeric strings from pvesh | retried through the helper `write` mode with typed values |
| `POST /cluster/ha/rules` schema uses `allOf` / `oneOf` | variants merged by the helper |
| Plugin option lists (storage, realm, SDN...) do not contain the object ID | required parameters of the call stay visible |
| The schema marks some parameters required although the API fills them (NFS `path`, fabric `redistribute`) | `*` is only a marker, the API validates |
| `/cluster/sdn/ipams/pve/status` lists only zones with IPAM `pve` **and** DHCP | message in the IPAM panel |
| `PUT /cluster/sdn/vnets/{vnet}/ips` fails ("can't find any subnet for ip") also with pvesh (PVE 9.2) | error displayed |
| SDN VNets need `source /etc/network/interfaces.d/*` | warning in the SDN panel (missing on pve1) |
| Network API writes add stanzas for detected interfaces (`iface wlo1 inet manual`) | none (harmless) |
| `qmpstatus` (paused) is not in `/cluster/resources` | Pause/Resume asks `status/current` |
| After a rollback with RAM, QEMU loads the state while the VM lock is held (≈10–20 s) | the next action may report a lock timeout; tests wait with `flock -n` |
| Container snapshots need a snapshot capable storage (not `dir`/raw) | tests use a temporary LVM-Thin pool |
| Destroying a CephFS needs its storage disabled/unmounted and the MDS stopped | done by `ceph_fs_destroy` before the API call |
| `pveceph purge` keeps `ceph.conf` when the local monitor is stopped ("Foreign MON address") | test teardown removes the leftovers |
| Ceph OSD start may be blocked by systemd start limits after a failed attempt | `systemctl reset-failed` in the tests |
| Upload API needs `tmpfilename` matching `/var/tmp/pveupload-<hex>` and moves the file | a copy with that name is used |
| Snippets cannot be uploaded through the API | copied into the storage path |
| Without a guest OS, ACPI reboot/shutdown time out | reported as an error |

## Lessons learned (bugs found by the tests)

- Never name a local variable `L`: it shadows the translation array and
  aborts the expansion silently.
- `IFS=$'\t' read -a` merges empty fields: use `tsv_split`.
- A bare `wait` also waits for the API co-process: always wait for PIDs.
- Key handlers must use the row key passed in `$2`, not the cursor (the
  tests and the mouse do not move the cursor).
- `REPLY` is overwritten by `T`/`Tf`: copy it before translating (the backup
  mode bug).
- Wait loops must not match themselves (`pgrep -f "[i]ntegration-test"`).
- Test writes of the CLI only on test guests: `pvetty guests start 101`
  during a CLI test started a real container of the user (1.1 development).
- Every loop reading keys must end when the terminal is gone: `read`
  fails at once on a closed terminal, and a loop that ignores it spins at
  100 % CPU forever (1.2.1: screen-test leftovers ran for hours). `read_key`
  exits on end of file; HUP / TERM exit directly.
- A whiptail `--menu` used as a toggle list toggles again on Enter on Ok:
  use `dlg_checklist`, or name the buttons (`DLG_OK_LABEL`).
- `printf %-Ns` counts bytes with some locales: pad with `fit` (multibyte
  glyphs in the help window).

## Tests

- `tools/selftest.sh`: renders every panel (read only, ~117 panels, 0 error).
- `tools/integration-test.sh`: read/write tests, see TESTING.md. Results of
  1.0.0 in TEST-RESULTS.md (raw outputs are not published: they contain
  the addresses and names of the test node).
- Before a run on a real node: back up `/etc/pve`, `/etc/network`,
  `/etc/hosts`, `/etc/apt` and the package list; afterwards compare them (the
  1.0.0 run left byte-identical files after removing a few traces of PVE
  itself, listed in TEST-RESULTS.md).
- Let's Encrypt allows 5 duplicate certificates per week: use
  `ACME_NO_ORDER=1` for repeated runs.

## Source control

Git repository in the project directory (since 1.1.0): `main` holds the
releases (tags `vX.Y.Z`), work is done on `develop`, one commit per feature.
`.githooks/pre-commit` runs `tools/lint.sh` and `tools/selftest.sh`
(`git config core.hooksPath .githooks`).

## Release procedure

1. Set `PVETTY_VERSION` in `lib/core.sh`, `VERSION`, and update
   `CHANGELOG.md` and the history above.
2. `tools/lint.sh`, `tools/selftest.sh`, `tools/screen-test.sh`.
3. Run the integration tests on a test node; update TEST-RESULTS.md.
4. `tools/i18n-extract.sh > lang/TEMPLATE.sh`.
5. Commit on `develop`, merge into `main` (`--no-ff`), tag `vX.Y.Z`.
6. Build the archive and the package: `tools/make-release.sh`,
   `tools/make-deb.sh` (in `../releases/`).

## Ideas for later

- Remote mode (HTTP API with a token) — see COMPARISON-devnullvoid-pvetui.md.

- Translations (lang/fr.sh from TEMPLATE.sh).
- Multi-node cluster tests (migration, replication, remote consoles).
- A text console for VMs through the QEMU VNC text mode is not possible;
  SPICE/noVNC stay out of scope.
