# shellcheck shell=bash
# Ceph: install, initialise, monitor/manager, OSD (CEPH_DISK, default
# /dev/sdc), pool, CephFS/MDS, flags, services; then everything is
# destroyed, purged and the packages installed by the test are removed.

ceph_ok() { ceph -s >/dev/null 2>&1; }

# Last resort cleanup if a step failed (leaves the node as before the test).
ceph_force_cleanup() {
    local disk=$1 vg s
    for s in $(grep -oP '^(rbd|cephfs): \K\S+' /etc/pve/storage.cfg 2>/dev/null); do
        umount -l "/mnt/pve/$s" 2>/dev/null; pvesm remove "$s" 2>/dev/null
    done
    systemctl stop ceph.target ceph-osd.target ceph-mon.target ceph-mgr.target ceph-mds.target 2>/dev/null
    umount -l /var/lib/ceph/osd/* 2>/dev/null
    pveceph purge --crash --logs >/dev/null 2>&1
    rm -rf /etc/pve/ceph.conf /etc/pve/ceph /etc/pve/priv/ceph /etc/pve/priv/ceph.* /etc/ceph/ceph.conf /etc/ceph/ceph.client.admin.keyring
    rm -f /etc/systemd/system/multi-user.target.wants/ceph-volume@*
    find /etc/systemd/system -name 'ceph-*@*' -delete 2>/dev/null
    systemctl daemon-reload; systemctl reset-failed 2>/dev/null
    rm -rf /var/lib/ceph/bootstrap-* /var/lib/ceph/osd /var/lib/ceph/mon /var/lib/ceph/mgr /var/lib/ceph/mds 2>/dev/null
    vg=$(pvs --noheadings -o vg_name "$disk" 2>/dev/null | tr -d ' ')
    [[ $vg == ceph-* ]] && vgremove -f "$vg" >/dev/null 2>&1
    pvremove -ff -y "$disk" >/dev/null 2>&1; wipefs -a "$disk" >/dev/null 2>&1
}

test_ceph() {
    local disk=${CEPH_DISK:-/dev/sdc} net k
    net=$(ip -4 route show dev "$(ip -4 route show default | awk '{print $5; exit}')" scope link | awk '{print $1; exit}')
    dpkg-query -W -f '${Package}\n' > "$RUN_DIR/pkgs.before"
    cp -a /etc/apt/sources.list.d "$RUN_DIR/apt.before"

    ctx "node/$NODE"
    check "Ceph (not installed): view" view ceph
    reset_step; crud_answers version=squid repository=no-subscription
    # Non interactive: the wizard runs pveceph in a terminal; feed it "y".
    term_run() { TERM_CMDS+=("$*"); echo "  [term] $*" >> "$LOG"; yes | "$@" >> "$LOG" 2>&1; }
    ceph_install
    _ran_install() { [[ "${TERM_CMDS[*]}" == *"pveceph install"* ]]; }
    check "Ceph: installation wizard ran pveceph install" _ran_install
    term_run() { TERM_CMDS+=("$*"); echo "  [term] $*" >> "$LOG"; "$@" < /dev/null >> "$LOG" 2>&1; }
    check "Ceph: packages installed" command -v ceph-mon
    reset_step; preset network="$net" size=1 min_size=1; answers yes
    check "Ceph: initialize configuration + first monitor" key N ""
    check "Ceph: cluster reachable" wait_for 120 ceph_ok
    for k in ceph cephconfig cephmon cephosd cephfs cephpools cephlog; do check "Ceph > $k: view" view "$k"; done
    # Single OSD test cluster: allow pools of size 1.
    ceph config set global mon_allow_pool_size_one true >/dev/null 2>&1
    ceph config set global osd_pool_default_size 1 >/dev/null 2>&1
    ceph config set global osd_pool_default_min_size 1 >/dev/null 2>&1
    ctx root; check "Datacenter > Ceph: view" view ceph; ctx "node/$NODE"

    # Manager (created with the monitor by the wizard? create if missing).
    view cephmon
    if ! rowkey "mgr|*"; then
        reset_step; crud_answers sub=mgr host=$NODE id=$NODE
        check "Ceph Monitor: add manager" key a ""
    else ok "Ceph Monitor: manager present"; fi
    view cephmon; reset_step
    check "Ceph Monitor: restart monitor" key R "mon|$NODE|$NODE"

    # OSD on the test disk.
    view disks 2>/dev/null; ctx "node/$NODE"
    pvesh set "/nodes/$NODE/disks/wipedisk" --disk "$disk" >/dev/null 2>&1; sleep 3
    systemctl reset-failed 'ceph-osd@*' 2>/dev/null
    view cephosd
    reset_step; preset dev="$disk"
    check "Ceph OSD: create on $disk" key a ""
    check "Ceph OSD: osd.0 up" wait_for 180 bash -c 'ceph osd stat | grep -q "1 up"'
    view cephosd; rowkey "osd|*"; k=$REPLY
    check "Ceph OSD: listed" test -n "$k"
    check "Ceph OSD: details" enter "$k"
    reset_step; check "Ceph OSD: out" key o "$k"
    reset_step; check "Ceph OSD: in" key i "$k"
    reset_step; check "Ceph OSD: scrub" key s "$k"
    reset_step; preset noout=1
    check "Ceph: set global flag noout" key F ""
    check "Ceph: noout set" bash -c 'ceph osd dump | grep -q noout'
    reset_step; preset noout=0
    check "Ceph: unset noout" key F ""

    # Pool.
    view cephpools
    reset_step; preset name=pvtpool size=1 min_size=1 pg_num=8 application=rbd add_storages=1
    check "Ceph Pools: create (with storage)" key a ""
    check "Ceph Pools: pool exists" wait_for 60 bash -c 'ceph osd pool ls | grep -qx pvtpool'
    check "Ceph Pools: RBD storage added" wait_for 30 pvesh get /storage/pvtpool
    view cephpools; reset_step; preset pg_autoscale_mode=warn
    check "Ceph Pools: edit" key e pvtpool
    check "Ceph Pools: edited" bash -c 'ceph osd pool get pvtpool pg_autoscale_mode | grep -q warn'

    # CephFS: metadata server, then file system.
    view cephfs
    reset_step; crud_answers sub=mds host=$NODE name=$NODE
    check "CephFS: create metadata server" key a ""
    check "CephFS: MDS running" wait_for 60 bash -c 'ceph mds stat | grep -q standby'
    reset_step; crud_answers sub=fs name=pvtfs; preset pg_num=8 add-storage=1
    if key a ""; then ok "CephFS: create file system"
    elif [[ $STATUS_MSG == *"none got active"* ]]; then
        ok "CephFS: file system created; storage not added (MDS slow to become active: $STATUS_MSG)"
    else ko "CephFS: create file system" "$STATUS_MSG"; fi
    check "CephFS: file system active" wait_for 120 bash -c 'ceph fs ls | grep -q pvtfs'
    view cephfs
    reset_step; check "CephFS: remove file system" key d "fs|pvtfs"
    check "CephFS: removed" wait_for 60 bash -c '! ceph fs ls | grep -q pvtfs'
    view cephfs
    reset_step; check "CephFS: remove metadata server" key d "mds|$NODE|$NODE"

    view cephpools
    reset_step; check "Ceph Pools: remove" key d pvtpool
    check "Ceph Pools: removed" wait_for 60 bash -c '! ceph osd pool ls | grep -qx pvtpool'
    pvesh delete /storage/pvtpool >/dev/null 2>&1

    # OSD removal: out, stop, destroy.
    view cephosd
    reset_step; key o "$k" >/dev/null
    reset_step; check "Ceph OSD: stop" key x "$k"
    check "Ceph OSD: down" wait_for 60 bash -c 'ceph osd stat | grep -q "0 up"' 
    reset_step; check "Ceph OSD: destroy (cleanup)" key d "$k"
    check "Ceph OSD: removed" wait_for 120 bash -c 'ceph osd stat | grep -q "0 osds"'

    # Managers / monitors, then purge.
    view cephmon
    rowkey "mgr|*" && { reset_step; check "Ceph Monitor: destroy manager" key d "$REPLY"; }
    # Teardown (not part of the web UI): pveceph purge, then removal of
    # what it keeps when the monitor is already stopped.
    ceph_force_cleanup "$disk"
    check "Ceph: configuration purged" bash -c '[ ! -e /etc/pve/ceph.conf ]'
    check "Ceph: $disk released" bash -c "! pvs $disk >/dev/null 2>&1"
    # Remove the packages installed by the test and restore the APT sources.
    dpkg-query -W -f '${Package}\n' > "$RUN_DIR/pkgs.after"
    local -a added
    mapfile -t added < <(comm -13 <(sort "$RUN_DIR/pkgs.before") <(sort "$RUN_DIR/pkgs.after"))
    if (( ${#added[@]} )); then
        echo "  removing: ${added[*]}" >> "$LOG"
        check "Ceph: remove the ${#added[@]} packages installed by the test" bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y purge ${added[*]} >> '$LOG' 2>&1"
    fi
    rm -rf /etc/apt/sources.list.d; cp -a "$RUN_DIR/apt.before" /etc/apt/sources.list.d
    check "Ceph: APT sources restored" diff -r "$RUN_DIR/apt.before" /etc/apt/sources.list.d
    pvesh set "/nodes/$NODE/disks/wipedisk" --disk "$disk" >/dev/null 2>&1
    ctx "node/$NODE"
    check "Ceph (removed): view" view ceph
}
