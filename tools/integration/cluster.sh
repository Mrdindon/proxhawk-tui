# shellcheck shell=bash
# Datacenter: notes, cluster, options, storage, backup jobs, metric servers,
# resource mappings, custom CPU models, notifications, support.

test_cluster() {
    local k old
    ctx root

    # Read-only overview panels.
    for k in search summary cluster support hafencing; do check "Datacenter > $k: view" view "$k"; done

    # Notes (edited in $EDITOR).
    check "Notes: view" view notes
    api_kv /cluster/options; old=${API_KV[description]-}
    editor_writes "proxhawk-tui test note"
    check "Notes: edit" key e ""
    check "Notes: saved" kv_is /cluster/options description "proxhawk-tui test note"
    if [[ -n $old ]]; then editor_writes "${old//$'\x1f'/$'\n'}"; else editor_writes ""; fi
    key e "" >/dev/null
    check "Notes: restored" kv_is /cluster/options description "${old%%+($'\x1f')}"

    # Cluster: join information (create/join are not executed on this node).
    view cluster
    check "Cluster: Join Information" key J ""

    # Options: keyboard, then restore.
    check "Options: view" view options
    api_kv /cluster/options; old=${API_KV[keyboard]-}
    reset_step; preset keyboard=fr-ca
    check "Options: edit keyboard" enter keyboard
    check "Options: keyboard saved" kv_is /cluster/options keyboard fr-ca
    reset_step; preset keyboard="$old"
    check "Options: keyboard restored" enter keyboard
    reset_step; preset max_workers=3
    check "Options: edit max_workers" enter max_workers
    check "Options: max_workers saved" kv_is /cluster/options max_workers 3
    reset_step; preset max_workers=""
    check "Options: max_workers reset to default" enter max_workers
    check "Options: max_workers removed" kv_is /cluster/options max_workers ""

    # Storage: a directory storage.
    mkdir -p /var/tmp/proxhawk-tui-test-dir
    pvesh delete /storage/proxhawk-tui-test-dir >/dev/null 2>&1
    check "Storage: view" view storage
    reset_step; crud_answers type=dir; preset storage=proxhawk-tui-test-dir path=/var/tmp/proxhawk-tui-test-dir content="iso,backup"
    check "Storage: add Directory" key a ""
    check "Storage: created" kv_is /storage/proxhawk-tui-test-dir path /var/tmp/proxhawk-tui-test-dir
    view storage; reset_step; preset content="iso,backup,vztmpl" prune-backups="keep-last=2"
    check "Storage: edit" key e proxhawk-tui-test-dir
    check "Storage: edited" kv_like /storage/proxhawk-tui-test-dir content "*vztmpl*"
    reset_step; crud_answers type=nfs; preset storage=proxhawk-tui-test-nfs server=127.0.0.1 export=/nonexistent content=iso disable=1
    check "Storage: add NFS (disabled)" key a ""
    check "Storage: NFS created" kv_is /storage/proxhawk-tui-test-nfs server 127.0.0.1
    view storage; reset_step
    check "Storage: remove NFS" key d proxhawk-tui-test-nfs
    reset_step; crud_answers type=pbs; preset storage=proxhawk-tui-test-pbs server=127.0.0.1 datastore=test username=root@pam password=x fingerprint="00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF" disable=1
    if key a ""; then ok "Storage: add PBS (disabled)"; view storage; reset_step; check "Storage: remove PBS" key d proxhawk-tui-test-pbs
    else ok "Storage: add PBS rejected by the API ($STATUS_MSG)"; fi
    # The directory storage is removed at the end of the storage section.

    # Backup jobs.
    check "Backup: view" view backup
    reset_step; preset schedule="sun 03:00" storage=local vmid=99999 enabled=0 comment="proxhawk-tui test job" mode=snapshot
    check "Backup: add job" key a ""
    view backup; rowkey "backup-*"; local job=""
    for k in "${C_SELK[@]}"; do api_kv "/cluster/backup/$k" && [[ ${API_KV[comment]-} == "proxhawk-tui test job" ]] && job=$k; done
    if [[ -n $job ]]; then
        ok "Backup: job listed ($job)"
        reset_step; preset comment="edited job" schedule="sat 02:30"
        check "Backup: edit job" key e "$job"
        check "Backup: edited" kv_is "/cluster/backup/$job" schedule "sat 02:30"
        reset_step
        check "Backup: job detail" key J "$job"
        reset_step
        check "Backup: remove job" key d "$job"
        check "Backup: removed" api_lacks /cluster/backup id "$job"
    else ko "Backup: job listed" "not found"; fi

    # Replication needs a second node.
    check "Replication: view" view replication
    reset_step; preset id=99999-0 target="$NODE" schedule="*/15"
    if key a ""; then ko "Replication: add (single node)" "unexpected success"; key d 99999-0
    else ok "Replication: add rejected on a single node ($STATUS_MSG)"; fi

    # Metric server.
    check "Metric Server: view" view metric
    reset_step; crud_answers id=pvtmetric type=influxdb; preset server=127.0.0.1 port=8089 disable=1
    check "Metric Server: add InfluxDB" key a ""
    check "Metric Server: created" kv_is /cluster/metrics/server/pvtmetric port 8089
    view metric; reset_step; preset port=8090
    check "Metric Server: edit" key e pvtmetric
    check "Metric Server: edited" kv_is /cluster/metrics/server/pvtmetric port 8090
    reset_step; crud_answers id=pvtgraphite type=graphite; preset server=127.0.0.1 port=2003 disable=1
    check "Metric Server: add Graphite" key a ""
    view metric; reset_step; check "Metric Server: remove Graphite" key d pvtgraphite
    reset_step; check "Metric Server: remove InfluxDB" key d pvtmetric
    check "Metric Server: removed" api_lacks /cluster/metrics/server id pvtmetric

    # Resource mappings: USB / PCI / directory.
    check "Resource Mappings: view" view mapping
    reset_step; crud_answers sub=usb; preset id=pvtusb map="node=$NODE,id=0bda:8812" description="proxhawk-tui usb"
    check "Mappings: add USB" key a ""
    check "Mappings: USB created" api_has /cluster/mapping/usb id pvtusb
    view mapping; reset_step; preset description="edited usb"
    check "Mappings: edit USB" key e "usb|pvtusb"
    check "Mappings: USB edited" kv_is /cluster/mapping/usb/pvtusb description "edited usb"
    local pci
    api_get rows "/nodes/$NODE/hardware/pci" "" "id,vendor,device"
    tsv_split pci "${API_ROWS[0]}"
    reset_step; crud_answers sub=pci; preset id=pvtpci map="node=$NODE,path=${pci[0]},id=${pci[1]#0x}:${pci[2]#0x}" description="proxhawk-tui pci"
    check "Mappings: add PCI" key a ""
    check "Mappings: PCI created" api_has /cluster/mapping/pci id pvtpci
    view mapping; reset_step; check "Mappings: remove PCI" key d "pci|pvtpci"
    reset_step; check "Mappings: remove USB" key d "usb|pvtusb"
    check "Mappings: USB removed" api_lacks /cluster/mapping/usb id pvtusb
    check "Directory Mappings: view" view dirmapping
    reset_step; preset id=pvtdir map="node=$NODE,path=/var/tmp/proxhawk-tui-test-dir" description="proxhawk-tui dir"
    check "Directory Mappings: add" key a ""
    check "Directory Mappings: created" api_has /cluster/mapping/dir id pvtdir
    view dirmapping; reset_step; preset description="edited dir"
    check "Directory Mappings: edit" key e pvtdir
    reset_step; check "Directory Mappings: remove" key d pvtdir

    # Custom CPU models.
    check "Custom CPU Models: view" view cputypes
    reset_step; preset cputype=custom-pvtcpu reported-model=kvm64 flags="+aes"
    check "Custom CPU Models: add" key a ""
    check "Custom CPU Models: created" api_has /cluster/qemu/custom-cpu-models cputype custom-pvtcpu
    view cputypes; reset_step; preset flags="+aes;+pcid"
    check "Custom CPU Models: edit" key e custom-pvtcpu
    reset_step; check "Custom CPU Models: remove" key d custom-pvtcpu

    # Notifications: targets of every type, test, matchers.
    check "Notifications: view" view notifications
    reset_step; crud_answers sub=target type=sendmail; preset name=pvt-sendmail mailto-user=root@pam comment="proxhawk-tui sendmail"
    check "Notifications: add sendmail target" key a ""
    check "Notifications: sendmail created" api_has /cluster/notifications/targets name pvt-sendmail
    view notifications; reset_step; preset comment="edited sendmail"
    check "Notifications: edit sendmail" key e "target|sendmail|pvt-sendmail"
    check "Notifications: sendmail edited" kv_is /cluster/notifications/endpoints/sendmail/pvt-sendmail comment "edited sendmail"
    reset_step
    check "Notifications: test target" key t "target|sendmail|pvt-sendmail"
    reset_step; crud_answers sub=target type=smtp; preset name=pvt-smtp server=127.0.0.1 from-address=proxhawk-tui@example.invalid mailto=root@localhost disable=1
    check "Notifications: add smtp target" key a ""
    reset_step; crud_answers sub=target type=gotify; preset name=pvt-gotify server=https://gotify.example.invalid token=abc disable=1
    check "Notifications: add gotify target" key a ""
    reset_step; crud_answers sub=target type=webhook; preset name=pvt-webhook url=https://hook.example.invalid method=post disable=1
    check "Notifications: add webhook target" key a ""
    reset_step; crud_answers sub=matcher; preset name=pvt-matcher target=pvt-sendmail match-severity=error comment="proxhawk-tui matcher" disable=1
    check "Notifications: add matcher" key a ""
    check "Notifications: matcher created" api_has /cluster/notifications/matchers name pvt-matcher
    view notifications; reset_step; preset comment="edited matcher"
    check "Notifications: edit matcher" key e "matcher|pvt-matcher"
    reset_step; check "Notifications: remove matcher" key d "matcher|pvt-matcher"
    for k in sendmail smtp gotify webhook; do
        reset_step; check "Notifications: remove $k target" key d "target|$k|pvt-$k"
    done
    check "Notifications: targets removed" api_lacks /cluster/notifications/targets name pvt-sendmail
}
