# pvetty — Test results

## 1.1.0 (2026-10-06)

Same node. New section `features` and regression run of `access`, `vm`, `ct`
(the 1.1 changes touch the API layer, the queue and the task handling):

| Section | Passed | Failed | Skipped |
|---------|-------:|-------:|--------:|
| `features` | 52 | 0 | 0 |
| `access`, `vm`, `ct` | 298 | 0 | 0 |

Also: `tools/lint.sh` OK, `tools/selftest.sh` every panel OK,
`tools/screen-test.sh` 8/8. The other sections are unchanged since 1.0.0.

## 1.0.0

Node: Proxmox VE 9.2.21 (pve-manager 9.2.21), single node `pve1`, kernel 7.0.14-20-pve, 2026-10-05.

Command: `tools/integration-test.sh` (all sections). The `vm` section was run again after a test fix (wait for the VM lock after a rollback with RAM), the `ceph` section in a separate run.

| Section | Passed | Failed | Skipped |
|---------|-------:|-------:|--------:|
| `access` | 63 | 0 | 0 |
| `cluster` | 85 | 0 | 0 |
| `firewall` | 52 | 0 | 0 |
| `sdn` | 71 | 0 | 0 |
| `acme` | 29 | 0 | 1 |
| `node` | 62 | 0 | 0 |
| `disks` | 34 | 0 | 0 |
| `vm` | 150 | 0 | 0 |
| `ct` | 85 | 0 | 0 |
| `storage` | 23 | 0 | 0 |
| `ceph` | 49 | 0 | 0 |
| **Total** | **703** | **0** | **1** |

## Notes

- **ACME certificate order and renewal** were run for real once (Let's
  Encrypt, DNS challenge with the existing Cloudflare plugin): both passed and
  a new certificate was installed. The final run uses `ACME_NO_ORDER=1` (the
  skipped check) to stay within the Let's Encrypt duplicate certificate limit;
  the previous valid certificate is restored by the test.
- **Ceph** was installed (`pveceph install`, Squid, no-subscription), then
  initialised, used (monitor, manager, OSD on `/dev/sdc`, pool with RBD
  storage, MDS, CephFS, flags, services) and completely removed: purge,
  removal of the 33 packages installed by the test, APT sources restored.
- **Disks** `/dev/sdb` (USB key) and `/dev/sdc` were wiped, partitioned and
  used for LVM, LVM-Thin, Directory, ZFS, the container snapshots (temporary
  LVM-Thin) and the Ceph OSD. Both are empty after the tests.
- **Firewall** of the datacenter was really enabled (rules compiled by
  `pve-firewall`, API still reachable) then disabled; a Linux bridge was
  created and applied on the node, then removed.
- After the tests `/etc/pve`, `/etc/network`, `/etc/hosts`,
  `/etc/resolv.conf`, the time zone, the APT sources and the installed
  packages are identical to the backup taken before the tests. The tests
  remove every object they create; a few traces left by Proxmox VE itself
  were then removed by hand to get byte-identical files: empty configuration
  files created on first use (`ha/*.cfg`, `sdn/*.cfg`, `mapping/*.cfg`...),
  the SDN IPAM state and MAC cache, the files of the deactivated ACME staging
  account, the `content` lists of `storage.cfg` rewritten in another order, a
  `iface wlo1 inet manual` stanza added by the network API, and the key of
  the restored certificate (same key, different PEM encoding).

## Known Proxmox VE issues met during the tests

| Issue | Behaviour in pvetty |
|-------|---------------------|
| `PUT /cluster/sdn/vnets/{vnet}/ips` (edit an IPAM mapping) fails with "can't find any subnet for ip", also with `pvesh` | the API error is displayed; remove + add works |
| Rust backed SDN endpoints (prefix lists, route maps) refuse the numeric strings sent by `pvesh` ("invalid type: string, expected u32") | pvetty retries through its API helper with typed values (`write` mode) |
| The schema of `POST /cluster/ha/rules` uses `allOf`/`oneOf` variants | merged by the helper so the form shows every field |
| `pveceph purge` keeps `ceph.conf` when the local monitor is already stopped ("Foreign MON address") | test teardown only (purge is not part of the web UI) |
| The SDN needs `source /etc/network/interfaces.d/*` in `/etc/network/interfaces` (missing on this node) | the SDN panel shows the same warning as the web UI; the test adds the line temporarily |
| Without a guest OS, ACPI reboot/shutdown time out | reported in the footer; the test accepts the timeout |

## Not executed on purpose (implemented, but irreversible or harmful on this node)

| Action | Reason |
|--------|--------|
| Datacenter › Cluster: Create Cluster / Join Cluster | turns the standalone node into a cluster member; undoing it requires manual corosync/pmxcfs surgery (Join Information was tested) |
| Node: Reboot / Shutdown | would stop the node running the tests |
| Node › Subscription: upload / check / remove key | could invalidate the subscription currently configured |
| Node › Certificates: Revoke | would revoke the production certificate |
| Bulk shutdown / suspend / migrate | would act on the existing VM 100 and CT 101 (bulk *start* was tested: only guests with "start at boot") |
| VM/CT migration, replication | single node: the refusal of the API is tested |

## Detailed results


### Permissions (`access`)

- ✔ Groups: view
- ✔ Groups: add
- ✔ Groups: created
- ✔ Groups: edit
- ✔ Groups: edited
- ✔ Users: view
- ✔ Users: add
- ✔ Users: created
- ✔ Users: edit
- ✔ Users: edited
- ✔ Users: change password
- ✔ API Tokens: view
- ✔ API Tokens: add
- ✔ API Tokens: secret returned
- ✔ API Tokens: created
- ✔ API Tokens: edit
- ✔ API Tokens: edited
- ✔ API Tokens: remove
- ✔ API Tokens: removed
- ✔ Two Factor: view
- ✔ Two Factor: add recovery keys
- ✔ Two Factor: keys returned
- ✔ Two Factor: add TOTP
- ✔ Two Factor: edit TOTP
- ✔ Two Factor: edited
- ✔ Users: unlock TFA
- ✔ Two Factor: remove 00000000-0000-4000-8000-000000000000
- ✔ Two Factor: remove recovery
- ✔ Two Factor: all removed
- ✔ Roles: view
- ✔ Roles: add
- ✔ Roles: created
- ✔ Roles: edit
- ✔ Roles: edited
- ✔ Pools: view
- ✔ Pools: add
- ✔ Pools: created
- ✔ Pools: edit
- ✔ Pools: edited
- ✔ Permissions: view
- ✔ Permissions: add user permission
- ✔ Permissions: created
- ✔ Permissions: add group permission
- ✔ Permissions: remove user permission
- ✔ Permissions: user removed
- ✔ Permissions: remove group permission
- ✔ Realms: view
- ✔ Realms: add LDAP
- ✔ Realms: created
- ✔ Realms: edit
- ✔ Realms: edited
- ✔ Realms: sync reports the LDAP error (Realm Sync: pvtldap: failed - Connection refused)
- ✔ Realms: add OpenID
- ✔ Realms: remove OpenID
- ✔ Realms: remove LDAP
- ✔ Realms: removed
- ✔ Pools: remove
- ✔ Pools: removed
- ✔ Roles: remove
- ✔ Users: remove
- ✔ Users: removed
- ✔ Groups: remove
- ✔ Groups: removed

### Datacenter configuration (`cluster`)

- ✔ Datacenter > search: view
- ✔ Datacenter > summary: view
- ✔ Datacenter > cluster: view
- ✔ Datacenter > support: view
- ✔ Datacenter > hafencing: view
- ✔ Notes: view
- ✔ Notes: edit
- ✔ Notes: saved
- ✔ Notes: restored
- ✔ Cluster: Join Information
- ✔ Options: view
- ✔ Options: edit keyboard
- ✔ Options: keyboard saved
- ✔ Options: keyboard restored
- ✔ Options: edit max_workers
- ✔ Options: max_workers saved
- ✔ Options: max_workers reset to default
- ✔ Options: max_workers removed
- ✔ Storage: view
- ✔ Storage: add Directory
- ✔ Storage: created
- ✔ Storage: edit
- ✔ Storage: edited
- ✔ Storage: add NFS (disabled)
- ✔ Storage: NFS created
- ✔ Storage: remove NFS
- ✔ Storage: add PBS (disabled)
- ✔ Storage: remove PBS
- ✔ Backup: view
- ✔ Backup: add job
- ✔ Backup: job listed (00000000-0000-4000-8000-000000000000)
- ✔ Backup: edit job
- ✔ Backup: edited
- ✔ Backup: job detail
- ✔ Backup: remove job
- ✔ Backup: removed
- ✔ Replication: view
- ✔ Replication: add rejected on a single node (Add: Replication Job: failed - type: property is missing and it is not optional)
- ✔ Metric Server: view
- ✔ Metric Server: add InfluxDB
- ✔ Metric Server: created
- ✔ Metric Server: edit
- ✔ Metric Server: edited
- ✔ Metric Server: add Graphite
- ✔ Metric Server: remove Graphite
- ✔ Metric Server: remove InfluxDB
- ✔ Metric Server: removed
- ✔ Resource Mappings: view
- ✔ Mappings: add USB
- ✔ Mappings: USB created
- ✔ Mappings: edit USB
- ✔ Mappings: USB edited
- ✔ Mappings: add PCI
- ✔ Mappings: PCI created
- ✔ Mappings: remove PCI
- ✔ Mappings: remove USB
- ✔ Mappings: USB removed
- ✔ Directory Mappings: view
- ✔ Directory Mappings: add
- ✔ Directory Mappings: created
- ✔ Directory Mappings: edit
- ✔ Directory Mappings: remove
- ✔ Custom CPU Models: view
- ✔ Custom CPU Models: add
- ✔ Custom CPU Models: created
- ✔ Custom CPU Models: edit
- ✔ Custom CPU Models: remove
- ✔ Notifications: view
- ✔ Notifications: add sendmail target
- ✔ Notifications: sendmail created
- ✔ Notifications: edit sendmail
- ✔ Notifications: sendmail edited
- ✔ Notifications: test target
- ✔ Notifications: add smtp target
- ✔ Notifications: add gotify target
- ✔ Notifications: add webhook target
- ✔ Notifications: add matcher
- ✔ Notifications: matcher created
- ✔ Notifications: edit matcher
- ✔ Notifications: remove matcher
- ✔ Notifications: remove sendmail target
- ✔ Notifications: remove smtp target
- ✔ Notifications: remove gotify target
- ✔ Notifications: remove webhook target
- ✔ Notifications: targets removed

### Firewall (`firewall`)

- ✔ Datacenter Firewall: view
- ✔ Datacenter Firewall: add rule
- ✔ Datacenter Firewall: add rule with macro
- ✔ Datacenter Firewall: edit rule
- ✔ Datacenter Firewall: rule edited
- ✔ Datacenter Firewall: move rule
- ✔ Datacenter Firewall: remove rule 1
- ✔ Datacenter Firewall: remove rule 2
- ✔ Datacenter Firewall: rules removed
- ✔ Datacenter Firewall: Options view
- ✔ Datacenter Firewall: enable
- ✔ Datacenter Firewall: enabled
- ✔ Datacenter Firewall: rules active
- ✔ Datacenter Firewall: API still reachable
- ✔ Datacenter Firewall: disable (default)
- ✔ Datacenter Firewall: disabled
- ✔ Datacenter Firewall: edit input policy
- ✔ Datacenter Firewall: reset input policy
- ✔ Security Group: view
- ✔ Security Group: add group
- ✔ Security Group: add rule
- ✔ Security Group: rule created
- ✔ Security Group: edit rule
- ✔ Security Group: remove rule
- ✔ Security Group: remove group
- ✔ Security Group: removed
- ✔ Alias: view
- ✔ Alias: add
- ✔ Alias: edit
- ✔ Alias: edited
- ✔ Alias: remove
- ✔ IPSet: view
- ✔ IPSet: add
- ✔ IPSet: add CIDR
- ✔ IPSet: CIDR created
- ✔ IPSet: edit CIDR
- ✔ IPSet: remove CIDR
- ✔ IPSet: remove
- ✔ Node Firewall: view
- ✔ Node Firewall: add rule
- ✔ Node Firewall: add rule with macro
- ✔ Node Firewall: edit rule
- ✔ Node Firewall: rule edited
- ✔ Node Firewall: move rule
- ✔ Node Firewall: remove rule 1
- ✔ Node Firewall: remove rule 2
- ✔ Node Firewall: rules removed
- ✔ Node Firewall: Options view
- ✔ Node Firewall: Log view
- ✔ Node Firewall: edit log level
- ✔ Node Firewall: log level saved
- ✔ Node Firewall: log level reset

### SDN (`sdn`)

- ✔ SDN: source line added to /etc/network/interfaces for the test
- ✔ SDN: view
- ✔ Zones: view
- ✔ Zones: add Simple
- ✔ Zones: created (pending)
- ✔ Zones: edit
- ✔ Zones: edited
- ✔ Zones: add VLAN
- ✔ VNets: view
- ✔ VNets: add
- ✔ VNets: created
- ✔ VNets: edit
- ✔ Subnets: add
- ✔ Subnets: edit
- ✔ SDN Options: view
- ✔ Controllers: add EVPN
- ✔ Controllers: edit
- ✔ IPAM: add PVE IPAM
- ✔ IPAM: created
- ✔ IPAM: phpIPAM connection error reported (Add: IPAM: phpIPAM: failed - create sdn ipam object failed: Can't connect to phpipam api: Invalid response from server: 500 Can't connect to ipam.example.invalid:443 (Name or service not known))
- ✔ DNS: PowerDNS connection error reported (Add: DNS: PowerDNS: failed - create sdn dns object failed: dns api error: Invalid response from server: 500 Can't connect to dns.example.invalid:443 (Name or service not known))
- ✔ Fabrics: view
- ✔ Fabrics: add OpenFabric
- ✔ Fabrics: edit
- ✔ Prefix Lists: view
- ✔ Prefix Lists: add
- ✔ Prefix Lists: add entry
- ✔ Prefix Lists: edit entry
- ✔ Prefix Lists: remove entry
- ✔ Route Maps: view
- ✔ Route Maps: add entry
- ✔ Route Maps: edit entry
- ✔ Route Maps: remove entry
- ✔ SDN: Apply
- ✔ SDN: VNet bridge pvtvn1 created
- ✔ SDN: zone pvtz1 in the tree
- ✔ SDN zone: content view
- ✔ SDN zone: ipvrf view
- ✔ SDN zone: macvrf view
- ✔ SDN zone: permissions view
- ✔ SDN zone: add permission
- ✔ SDN zone: remove permission
- ✔ Zones: add Simple zone with DHCP
- ✔ VNets: add second VNet
- ✔ Subnets: add (DHCP zone)
- ✔ IPAM: view
- ✔ IPAM: add IP mapping
- ✔ IPAM: mapping listed
- ✔ IPAM: edit IP mapping - API error reported (known PVE issue: Edit: IP Mapping pvtvn4 pvtz4 10.96.0.50 BC:24:11:00:99:50: failed - can't find any subnet for ip  at /usr/share/perl5/PVE/Network/SDN/Subnets.pm line 115.)
- ✔ IPAM: remove IP mapping
- ✔ VNet Firewall: view
- ✔ VNet Firewall: add rule
- ✔ VNet Firewall: edit rule
- ✔ VNet Firewall: remove rule
- ✔ VNet Firewall: edit options
- ✔ Subnets: remove (pvtvn1)
- ✔ VNets: remove pvtvn1
- ✔ Subnets: remove (pvtvn4)
- ✔ VNets: remove pvtvn4
- ✔ Zones: remove pvtz1
- ✔ Zones: remove pvtz2
- ✔ Zones: remove pvtz4
- ✔ Controllers: remove
- ✔ IPAM: remove
- ✔ Fabrics: remove
- ✔ Prefix Lists: remove
- ✔ SDN: Apply (cleanup)
- ✔ SDN: VNet bridge removed
- ✔ SDN: Rollback pending changes
- ✔ SDN: pending zone discarded
- ✔ SDN: /etc/network/interfaces restored

### ACME and certificates (`acme`)

- ✔ ACME: view
- ✔ ACME: add standalone plugin
- ✔ ACME: standalone created
- ✔ ACME: edit standalone plugin
- ✔ ACME: standalone plugin edited
- ✔ ACME: add DNS plugin (Cloudflare)
- ✔ ACME: DNS plugin data stored
- ✔ ACME: edit DNS plugin
- ✔ ACME: DNS plugin edited
- ✔ ACME: remove plugin pvt-standalone
- ✔ ACME: remove plugin pvt-dns
- ✔ ACME: register staging account
- ✔ ACME: account listed
- ✔ ACME: account details
- ✔ ACME: edit account
- ✔ ACME: deactivate account
- ✔ ACME: account removed
- ✔ Certificates: view
- ✔ Certificates: add ACME domain
- ✔ Certificates: domain saved
- ✔ Certificates: edit domain
- ✔ Certificates: remove domain
- ✔ Certificates: edit ACME account
- ✔ Certificates: view certificate
- ✔ Certificates: upload custom certificate
- ✔ Certificates: custom certificate active
- ✔ Certificates: delete custom certificate
- ✔ Certificates: custom certificate removed
- – Certificates: order / renew  -- ACME_NO_ORDER=1
- ✔ Certificates: previous certificate restored

### Node (`node`)

- ✔ Node > search: view
- ✔ Node > summary: view
- ✔ Node > syslog: view
- ✔ Node > replication: view
- ✔ Node > subscription: view
- ✔ Node Notes: edit
- ✔ Node Notes: saved
- ✔ Node Notes: restored
- ✔ Shell: view
- ✔ Shell: login shell started
- ✔ System: view
- ✔ System: restart cron
- ✔ System: cron active
- ✔ System: stop cron
- ✔ System: cron stopped
- ✔ System: start cron
- ✔ System: cron running
- ✔ System: service status
- ✔ DNS: view
- ✔ DNS: edit
- ✔ DNS: saved
- ✔ DNS: restored
- ✔ DNS: dns1 kept
- ✔ DNS: resolv.conf ok
- ✔ Hosts: view
- ✔ Hosts: edit
- ✔ Hosts: saved
- ✔ Hosts: restored
- ✔ Options: view
- ✔ Options: edit start delay
- ✔ Options: saved
- ✔ Options: reset start delay
- ✔ Time: view
- ✔ Time: set time zone
- ✔ Time: time zone saved
- ✔ Time: time zone restored
- ✔ Time: restored
- ✔ Network: view
- ✔ Network: add Linux Bridge
- ✔ Network: pending changes shown
- ✔ Network: edit bridge
- ✔ Network: apply configuration
- ✔ Network: vmbr99 up with its address
- ✔ Network: add VLAN
- ✔ Network: revert pending changes
- ✔ Network: VLAN discarded
- ✔ Network: remove bridge
- ✔ Network: apply removal
- ✔ Network: vmbr99 removed
- ✔ Updates: view
- ✔ Updates: refresh package database
- ✔ Updates: refresh task OK
- ✔ Updates: upgrade (terminal)
- ✔ Repositories: view
- ✔ Repositories: add standard repository (test)
- ✔ Repositories: test repository configured
- ✔ Repositories: toggle a repository
- ✔ Repositories: toggle back
- ✔ Repositories: files restored
- ✔ Task History: view
- ✔ Task History: task log
- ✔ Bulk Actions: start all (onboot guests)

### Disks (`disks`)

- ✔ Disks: view
- ✔ Disks: S.M.A.R.T. /dev/sdb
- ✔ Disks: S.M.A.R.T. /dev/sdc
- ✔ Disks: system disk untouched
- ✔ Disks: wipe /dev/sdb
- ✔ Disks: /dev/sdb has no partition
- ✔ Disks: initialize GPT on /dev/sdb
- ✔ Disks: GPT on /dev/sdb
- ✔ LVM: view
- ✔ LVM: create volume group
- ✔ LVM: volume group present
- ✔ LVM: storage added
- ✔ LVM: remove volume group
- ✔ LVM: removed
- ✔ LVM: storage removed
- ✔ LVM-Thin: view
- ✔ LVM-Thin: create thinpool
- ✔ LVM-Thin: thinpool present
- ✔ LVM-Thin: remove thinpool
- ✔ LVM-Thin: removed
- ✔ Directory: view
- ✔ Directory: create (ext4)
- ✔ Directory: mounted
- ✔ Directory: remove
- ✔ Directory: unmounted
- ✔ Disks: wipe /dev/sdc
- ✔ ZFS: view
- ✔ ZFS: create pool
- ✔ ZFS: pool online
- ✔ ZFS: pool detail
- ✔ ZFS: remove pool
- ✔ ZFS: pool destroyed
- ✔ Disks: wipe /dev/sdc (final)
- ✔ Disks: /dev/sdc empty

### Virtual machine (`vm`)

- ✔ Create VM wizard
- ✔ VM created
- ✔ VM > summary: view
- ✔ VM > console: view
- ✔ VM > hardware: view
- ✔ VM > cloudinit: view
- ✔ VM > options: view
- ✔ VM > tasks: view
- ✔ VM > monitor: view
- ✔ VM > backup: view
- ✔ VM > replication: view
- ✔ VM > snapshots: view
- ✔ VM > firewall: view
- ✔ VM > fwoptions: view
- ✔ VM > fwalias: view
- ✔ VM > fwipset: view
- ✔ VM > fwlog: view
- ✔ VM > permissions: view
- ✔ Hardware: add Hard Disk
- ✔ Hardware: scsi1 present
- ✔ Hardware: add CD/DVD Drive
- ✔ Hardware: add Network Device
- ✔ Hardware: net1 present
- ✔ Hardware: add EFI Disk
- ✔ Hardware: efidisk0 present
- ✔ Hardware: add TPM State
- ✔ Hardware: add Serial Port
- ✔ Hardware: serial0 = socket
- ✔ Hardware: add CloudInit Drive
- ✔ Hardware: CloudInit drive present
- ✔ Hardware: add Audio Device
- ✔ Hardware: add VirtIO RNG
- ✔ Hardware: add USB Device
- ✔ Hardware: add PCI Device
- ✔ Hardware: add Virtiofs
- ✔ Hardware: edit Memory
- ✔ Hardware: memory 768
- ✔ Hardware: edit Processors
- ✔ Hardware: 2 cores
- ✔ Hardware: edit Network Device
- ✔ Hardware: net1 model e1000
- ✔ Hardware: resize scsi1
- ✔ Hardware: scsi1 resized to 2G
- ✔ Hardware: move scsi1 to local
- ✔ Hardware: scsi1 on local
- ✔ Hardware: detach scsi1
- ✔ Hardware: scsi1 became unused0
- ✔ Hardware: delete unused0
- ✔ Hardware: remove usb0
- ✔ Hardware: remove hostpci0
- ✔ Hardware: remove virtiofs0
- ✔ Hardware: remove audio0
- ✔ Hardware: remove rng0
- ✔ Hardware: remove tpmstate0
- ✔ Hardware: remove efidisk0
- ✔ Hardware: remove ide0
- ✔ Cloud-Init: edit user
- ✔ Cloud-Init: edit IP config
- ✔ Cloud-Init: ipconfig0 saved
- ✔ Cloud-Init: regenerate image
- ✔ Options: rename
- ✔ Options: start at boot / order
- ✔ Options: startup saved
- ✔ Options: QEMU Guest Agent
- ✔ Options: protection on
- ✔ Options: protection reset
- ✔ Options: reset startup to default
- ✔ Notes: edit
- ✔ Notes: saved
- ✔ Permissions: add
- ✔ Permissions: remove
- ✔ Manage HA: add
- ✔ Manage HA: change state
- ✔ HA: resource listed
- ✔ HA: edit resource
- ✔ HA Rules: add node affinity
- ✔ HA Rules: edit
- ✔ HA Rules: remove
- ✔ Manage HA: remove
- ✔ Pool: members view
- ✔ Pool: add VM
- ✔ Pool: VM member
- ✔ Pool: add storage
- ✔ Pool: remove VM
- ✔ Pool: remove storage
- ✔ Pool: summary view
- ✔ Pool: permissions view
- ✔ Start
- ✔ VM running
- ✔ Pause
- ✔ VM paused
- ✔ Resume
- ✔ VM resumed
- ✔ Reset
- ✔ Reboot: ACPI timeout reported (no guest OS: VM 9901 (pvetty-test-vm2) - Reboot: failed - VM quit/powerdown failed - got timeout)
- ✔ VM running
- ✔ Monitor: command
- ✔ Monitor: output
- ✔ Console: qm terminal used (serial port)
- ✔ Snapshots: take (with RAM)
- ✔ Snapshots: listed
- ✔ Snapshots: edit description
- ✔ Snapshots: rollback
- ✔ VM lock released after rollback
- ✔ Snapshots: remove
- ✔ Snapshots: removed
- ✔ Hibernate
- ✔ VM hibernated (stopped with state)
- ✔ Start (resume from hibernation)
- ✔ Stop
- ✔ VM stopped
- ✔ VM Firewall: view
- ✔ VM Firewall: add rule
- ✔ VM Firewall: add rule with macro
- ✔ VM Firewall: edit rule
- ✔ VM Firewall: rule edited
- ✔ VM Firewall: move rule
- ✔ VM Firewall: remove rule 1
- ✔ VM Firewall: remove rule 2
- ✔ VM Firewall: rules removed
- ✔ VM Firewall: Options view
- ✔ VM Firewall: Log view
- ✔ VM Firewall: enable
- ✔ VM Firewall: disable
- ✔ VM Alias: add
- ✔ VM Alias: remove
- ✔ VM IPSet: add
- ✔ VM IPSet: remove
- ✔ Backup now
- ✔ Backup: listed
- ✔ Backup: edit notes
- ✔ Backup: protect
- ✔ Backup: unprotect
- ✔ Backup: show configuration
- ✔ Storage Backups: restore to VM 9902
- ✔ Restored VM 9902 exists
- ✔ Storage Backups: prune
- ✔ Backup: remove
- ✔ Replication: refused on a single node (Add: Replication Job: failed - type: property is missing and it is not optional)
- ✔ Clone (full)
- ✔ Clone 9903 exists
- ✔ Convert clone to template
- ✔ 9903 is a template
- ✔ Migrate (no other node)
- ✔ Remove template 9903
- ✔ Remove restored VM 9902
- ✔ SSH: IP addresses found for VM 100 (192.0.2.204)
- ✔ SSH: proposed instead of the serial console
- ✔ Remove VM 9901
- ✔ VM removed

### Container (`ct`)

- ✔ CT storage: temporary LVM-Thin pool on /dev/sdb
- ✔ Create CT wizard
- ✔ CT created
- ✔ CT > summary: view
- ✔ CT > console: view
- ✔ CT > resources: view
- ✔ CT > network: view
- ✔ CT > dns: view
- ✔ CT > options: view
- ✔ CT > tasks: view
- ✔ CT > backup: view
- ✔ CT > replication: view
- ✔ CT > snapshots: view
- ✔ CT > firewall: view
- ✔ CT > fwoptions: view
- ✔ CT > fwalias: view
- ✔ CT > fwipset: view
- ✔ CT > fwlog: view
- ✔ CT > permissions: view
- ✔ Resources: edit memory/swap
- ✔ Resources: memory 768
- ✔ Resources: edit cores
- ✔ Resources: add Mount Point
- ✔ Resources: mp0 present
- ✔ Resources: resize rootfs
- ✔ Resources: rootfs 5G
- ✔ Resources: move mp0 to local
- ✔ Resources: mp0 on local
- ✔ Resources: detach mp0
- ✔ Resources: mp0 -> unused0
- ✔ Resources: delete unused0
- ✔ Network: add device
- ✔ Network: net1 present
- ✔ Network: edit device
- ✔ Network: net1 edited
- ✔ Network: remove device
- ✔ DNS: edit
- ✔ DNS: hostname
- ✔ DNS: hostname saved
- ✔ DNS: reset nameserver
- ✔ Options: features
- ✔ Options: nesting
- ✔ Options: startup
- ✔ Options: protection
- ✔ Options: reset protection
- ✔ Start
- ✔ CT running
- ✔ Console: pct enter used
- ✔ CT: command runs inside
- ✔ Summary with IPs
- ✔ Reboot
- ✔ CT running after reboot
- ✔ Snapshots: take
- ✔ Snapshots: listed
- ✔ Snapshots: edit
- ✔ Shutdown
- ✔ CT stopped
- ✔ Snapshots: rollback
- ✔ Snapshots: remove
- ✔ CT Firewall: view
- ✔ CT Firewall: add rule
- ✔ CT Firewall: add rule with macro
- ✔ CT Firewall: edit rule
- ✔ CT Firewall: rule edited
- ✔ CT Firewall: move rule
- ✔ CT Firewall: remove rule 1
- ✔ CT Firewall: remove rule 2
- ✔ CT Firewall: rules removed
- ✔ CT Firewall: Options view
- ✔ CT Firewall: Log view
- ✔ Permissions: add
- ✔ Permissions: remove
- ✔ Backup now
- ✔ Backup: listed
- ✔ Backup: restore over the container
- ✔ CT still present after restore
- ✔ Backup: remove
- ✔ Clone (full)
- ✔ Clone 9913 exists
- ✔ Convert clone to template
- ✔ 9913 is a template
- ✔ Remove template 9913
- ✔ Remove CT 9911
- ✔ CT removed
- ✔ CT storage: temporary LVM-Thin pool removed

### Storage (`storage`)

- ✔ Storage > summary: view
- ✔ Storage > iso: view
- ✔ Storage > vztmpl: view
- ✔ Storage > backup: view
- ✔ Storage > snippets: view
- ✔ Storage > import: view
- ✔ Storage > permissions: view
- ✔ ISO Images: upload
- ✔ ISO Images: uploaded
- ✔ ISO Images: remove
- ✔ ISO Images: removed
- ✔ ISO Images: download from URL
- ✔ ISO Images: downloaded
- ✔ ISO Images: remove download
- ✔ Snippets: upload
- ✔ Snippets: uploaded
- ✔ Snippets: remove
- ✔ CT Templates: download alpine-3.23-default_20260116_amd64.tar.xz
- ✔ CT Templates: downloaded
- ✔ CT Templates: remove
- ✔ Storage Permissions: add
- ✔ Storage Permissions: remove
- ✔ Storage: remove test storage

### Ceph (`ceph`)

- ✔ Ceph (not installed): view
- ✔ Ceph: installation wizard ran pveceph install
- ✔ Ceph: packages installed
- ✔ Ceph: initialize configuration + first monitor
- ✔ Ceph: cluster reachable
- ✔ Ceph > ceph: view
- ✔ Ceph > cephconfig: view
- ✔ Ceph > cephmon: view
- ✔ Ceph > cephosd: view
- ✔ Ceph > cephfs: view
- ✔ Ceph > cephpools: view
- ✔ Ceph > cephlog: view
- ✔ Datacenter > Ceph: view
- ✔ Ceph Monitor: manager present
- ✔ Ceph Monitor: restart monitor
- ✔ Ceph OSD: create on /dev/sdc
- ✔ Ceph OSD: osd.0 up
- ✔ Ceph OSD: listed
- ✔ Ceph OSD: details
- ✔ Ceph OSD: out
- ✔ Ceph OSD: in
- ✔ Ceph OSD: scrub
- ✔ Ceph: set global flag noout
- ✔ Ceph: noout set
- ✔ Ceph: unset noout
- ✔ Ceph Pools: create (with storage)
- ✔ Ceph Pools: pool exists
- ✔ Ceph Pools: RBD storage added
- ✔ Ceph Pools: edit
- ✔ Ceph Pools: edited
- ✔ CephFS: create metadata server
- ✔ CephFS: MDS running
- ✔ CephFS: create file system
- ✔ CephFS: file system active
- ✔ CephFS: remove file system
- ✔ CephFS: removed
- ✔ CephFS: remove metadata server
- ✔ Ceph Pools: remove
- ✔ Ceph Pools: removed
- ✔ Ceph OSD: stop
- ✔ Ceph OSD: down
- ✔ Ceph OSD: destroy (cleanup)
- ✔ Ceph OSD: removed
- ✔ Ceph Monitor: destroy manager
- ✔ Ceph: configuration purged
- ✔ Ceph: /dev/sdc released
- ✔ Ceph: remove the 33 packages installed by the test
- ✔ Ceph: APT sources restored
- ✔ Ceph (removed): view
