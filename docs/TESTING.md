# proxhawk-tui — Testing

Four tools are provided: lint, self test, screen tests and integration tests.

## 0. Lint

```bash
tools/lint.sh      # bash -n, perl -c, shellcheck -S warning (.shellcheckrc)
```

Run by the git pre-commit hook with the self test
(`git config core.hooksPath .githooks`).

## 1. Self test (read only)

```bash
tools/selftest.sh                       # one resource of each type
tools/selftest.sh qemu/100 node/pve1    # given resources
```

Renders every panel of the menus without the interface and reports the time,
the number of lines and any error written by a panel. It does not change
anything.

## 2. Screen tests (golden files)

```bash
tools/screen-test.sh                  # compare every scenario
tools/screen-test.sh dc_help          # some scenarios
tools/screen-test.sh update           # accept the current screens
tools/screen-test.sh record           # re-record the API answers (read only), then update
```

Each scenario of `tests/screens/scenarios` (`name key key...`) starts proxhawk-tui
in a detached tmux session (120×36, `unicode` icons, `default` theme, UTC,
frozen clock), sends the keys and compares the screen text with
`tests/screens/golden/<name>.txt`; a difference is shown as a diff.

The API is not called: `backend = replay` serves the answers recorded in
`tests/screens/fixture` (`PROXHAWK_TUI_RECORD`), so the tests give the same result
on any machine with bash and tmux, and catch layout regressions. Re-record
when a panel reads new API data (it would show `not recorded: ...`). The
fixture is an anonymised snapshot of a node (no real names or addresses).

## 3. Integration tests (read and write)

```bash
tools/integration-test.sh                     # every section
tools/integration-test.sh access node vm      # some sections (see the list in the script, e.g. features)
LOG=/tmp/it.log tools/integration-test.sh sdn
```

> **The integration tests modify the node.** Run them on a test system or
> after a backup of `/etc/pve`, `/etc/network`, `/etc/hosts`, `/etc/apt`.

How it works:

- the real proxhawk-tui functions are used: panels are rendered, keys are pressed
  (`a`, `e`, `d`, `Enter`, toolbar and panel keys), wizards and menus are run;
- dialogs are simulated: answers are queued, forms are submitted with preset
  values (`FORM_PRESET`), editors write a given text;
- worker tasks are followed until they stop (`API_WAIT_TASKS=1`) so that their
  real result is checked;
- every write is verified by reading the API (or the system: interfaces, LVM,
  ZFS, mounts, `/etc/hosts`, `resolv.conf`...) back;
- every test object is removed and every changed setting is restored at the
  end of its section (`proxhawk-tui-test*` / `pvt*` names, VMIDs 9901-9919).

| Section | Content |
|---------|---------|
| `access` | users (password, TFA unlock), API tokens, TFA (recovery keys, TOTP), groups, roles, pools, ACL (user, group), realms (LDAP with sync, OpenID) |
| `cluster` | datacenter notes, join information, options, storage (Directory, NFS, PBS), backup jobs (edit, detail), replication, metric servers, PCI/USB/directory mappings, custom CPU models, notification targets (Sendmail, SMTP, Gotify, Webhook, test) and matchers |
| `firewall` | rules (add, edit, move, remove), datacenter firewall enabled for real then disabled, policies, security groups and rules, aliases, IPSets and entries, node options and log |
| `sdn` | zones, VNets, subnets, controllers, IPAM, DNS, fabrics, prefix lists, route maps, apply (the VNet bridge appears on the node), zone panels and permissions, IPAM mappings, VNet firewall, rollback |
| `acme` | challenge plugins (standalone, DNS), account registration on the Let's Encrypt staging directory, node ACME domains and account, custom certificate upload/removal, **real certificate order and renewal** (`ACME_NO_ORDER=1` skips them) |
| `node` | notes, shell, services, DNS, hosts, options, time zone, network (bridge created, applied, removed; revert), package database refresh, upgrade, repositories, task log, bulk start |
| `disks` | S.M.A.R.T., wipe, GPT, LVM, LVM-Thin, Directory (ext4), ZFS on `DISK_A` / `DISK_B` (default `/dev/sdb`, `/dev/sdc`; **erased**) |
| `vm` | Create VM wizard, every Hardware device type, edit memory/CPU/network, resize/move/detach/delete disks, cloud-init, options, notes, ACL, HA and affinity rule, pool membership, start/pause/resume/reset/reboot, monitor, serial console, snapshots with RAM, hibernate, guest firewall, backup now, backup notes/protection, restore, prune, replication, clone, template, migrate, remove; SSH address discovery for a Linux VM |
| `ct` | Create CT wizard, resources (mount point, resize, move), network, DNS, options, start/reboot/shutdown, `pct enter`, snapshots (temporary LVM-Thin pool on `DISK_A`), firewall, ACL, backup and restore, clone, template, remove |
| `storage` | ISO upload, download from URL, snippets upload, CT template download, storage permissions |
| `ceph` | `pveceph install`, initialisation, monitor/manager, OSD on `CEPH_DISK` (default `/dev/sdc`, **erased**), out/in/scrub, global flags, pool (with RBD storage), MDS and CephFS, then everything destroyed, `pveceph purge` and removal of the packages installed by the test |

Environment variables: `LOG`, `DISK_A`, `DISK_B`, `CEPH_DISK`,
`TEST_STORAGE` (storage of the test guests, default `VM`), `ACME_CONTACT`,
`ACME_NO_ORDER`.

## Last results

See [TEST-RESULTS.md](TEST-RESULTS.md).
