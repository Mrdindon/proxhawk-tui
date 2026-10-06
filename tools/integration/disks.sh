# shellcheck shell=bash
# Disks: S.M.A.R.T., wipe, GPT, LVM, LVM-Thin, Directory, ZFS.
# DISK_A / DISK_B: disks that may be erased (default /dev/sdb, /dev/sdc).

test_disks() {
    local a=${DISK_A:-/dev/sdb} b=${DISK_B:-/dev/sdc}
    ctx "node/$NODE"
    check "Disks: view" view disks
    check "Disks: S.M.A.R.T. $a" enter "$a"
    check "Disks: S.M.A.R.T. $b" enter "$b"

    # The system disk is refused by the confirmation (wrong name typed).
    reset_step; answers "nope"
    key W /dev/sda >/dev/null 2>&1
    check "Disks: system disk untouched" bash -c 'lsblk -no NAME /dev/sda | grep -q sda3'

    reset_step; crud_answers confirm=$a
    check "Disks: wipe $a" key W "$a"
    check "Disks: $a has no partition" bash -c "[[ \$(lsblk -no NAME $a | wc -l) == 1 ]]"
    reset_step; crud_answers confirm=$a
    check "Disks: initialize GPT on $a" key G "$a"
    check "Disks: GPT on $a" wait_for 10 bash -c "pvesh get /nodes/$NODE/disks/list --output-format json | grep -q '\"devpath\":\"$a\".*\"gpt\":1\|\"gpt\":1.*\"devpath\":\"$a\"'"
    crud_answers confirm=$a; key W "$a" >/dev/null

    # LVM.
    check "LVM: view" view lvm
    reset_step; preset device="$a" name=pvtvg add_storage=1
    check "LVM: create volume group" key a ""
    check "LVM: volume group present" wait_for 20 vgs pvtvg
    check "LVM: storage added" kv_is /storage/pvtvg vgname pvtvg
    view lvm; reset_step
    check "LVM: remove volume group" key d pvtvg
    check "LVM: removed" wait_for 20 bash -c '! vgs pvtvg'
    check "LVM: storage removed" bash -c '! pvesh get /storage/pvtvg >/dev/null 2>&1'

    # LVM-Thin.
    check "LVM-Thin: view" view lvmthin
    reset_step; preset device="$a" name=pvtthin add_storage=1
    check "LVM-Thin: create thinpool" key a ""
    check "LVM-Thin: thinpool present" wait_for 20 lvs pvtthin/pvtthin
    view lvmthin; reset_step
    check "LVM-Thin: remove thinpool" key d "pvtthin|pvtthin"
    check "LVM-Thin: removed" wait_for 20 bash -c '! vgs pvtthin'

    # Directory.
    check "Directory: view" view directory
    reset_step; preset device="$a" name=pvtdirfs filesystem=ext4 add_storage=1
    check "Directory: create (ext4)" key a ""
    check "Directory: mounted" wait_for 30 mountpoint -q /mnt/pve/pvtdirfs
    view directory; reset_step
    check "Directory: remove" key d pvtdirfs
    check "Directory: unmounted" wait_for 20 bash -c '! mountpoint -q /mnt/pve/pvtdirfs'

    # ZFS (on the second disk, wiped first).
    view disks; reset_step; crud_answers confirm=$b
    check "Disks: wipe $b" key W "$b"
    check "ZFS: view" view zfs
    reset_step; preset name=pvtzfs devices="$b" raidlevel=single compression=lz4 ashift=12 add_storage=1
    check "ZFS: create pool" key a ""
    check "ZFS: pool online" wait_for 30 bash -c 'zpool list -H -o health pvtzfs | grep -q ONLINE'
    view zfs
    check "ZFS: pool detail" enter pvtzfs
    reset_step
    check "ZFS: remove pool" key d pvtzfs
    check "ZFS: pool destroyed" wait_for 30 bash -c '! zpool list pvtzfs'

    # Leave both disks empty.
    view disks
    reset_step; crud_answers confirm=$a; key W "$a" >/dev/null
    reset_step; crud_answers confirm=$b
    check "Disks: wipe $b (final)" key W "$b"
    check "Disks: $b empty" bash -c "[[ \$(lsblk -no NAME $b | wc -l) == 1 ]]"
}
