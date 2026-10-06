# shellcheck shell=bash
# Node panels: summary, notes, shell, services, network, DNS, hosts, options,
# time, syslog, updates, repositories, replication, tasks, subscription.

test_node() {
    local k old
    ctx "node/$NODE"
    for k in search summary syslog replication subscription; do check "Node > $k: view" view "$k"; done

    # Notes.
    view notes
    api_kv "/nodes/$NODE/config"; old=${API_KV[description]-}
    editor_writes "pvetty node note"
    check "Node Notes: edit" key e ""
    check "Node Notes: saved" kv_is "/nodes/$NODE/config" description "pvetty node note"
    editor_writes "${old//$'\x1f'/$'\n'}"; key e "" >/dev/null
    check "Node Notes: restored" kv_is "/nodes/$NODE/config" description "${old%%+($'\x1f')}"

    # Shell (runs non-interactively here).
    check "Shell: view" view shell
    TERM_CMDS=()
    enter shell >/dev/null
    check "Shell: login shell started" bash -c "[[ '${TERM_CMDS[*]}' == *exec* ]]"

    # System: services.
    check "System: view" view system
    reset_step; check "System: restart cron" key R cron
    check "System: cron active" wait_for 10 systemctl is-active --quiet cron
    reset_step; check "System: stop cron" key x cron
    check "System: cron stopped" wait_for 10 bash -c '! systemctl is-active --quiet cron'
    reset_step; check "System: start cron" key S cron
    check "System: cron running" wait_for 10 systemctl is-active --quiet cron
    check "System: service status" enter cron

    # DNS: change, then restore.
    check "DNS: view" view dns
    api_kv "/nodes/$NODE/dns"; local -A dns=(); for k in search dns1 dns2 dns3; do dns[$k]=${API_KV[$k]-}; done
    reset_step; preset dns2=9.9.9.9
    check "DNS: edit" enter ""
    check "DNS: saved" kv_is "/nodes/$NODE/dns" dns2 9.9.9.9
    reset_step; preset dns2="${dns[dns2]}"
    check "DNS: restored" enter ""
    check "DNS: dns1 kept" kv_is "/nodes/$NODE/dns" dns1 "${dns[dns1]}"
    check "DNS: resolv.conf ok" grep -q "nameserver ${dns[dns1]}" /etc/resolv.conf

    # Hosts.
    check "Hosts: view" view hosts
    cp /etc/hosts "$RUN_DIR/hosts.orig"
    editor_writes "$(cat /etc/hosts)"$'\n'"# pvetty test entry"
    check "Hosts: edit" key e ""
    check "Hosts: saved" grep -q "pvetty test entry" /etc/hosts
    editor_writes "$(cat "$RUN_DIR/hosts.orig")"
    key e "" >/dev/null
    check "Hosts: restored" cmp -s /etc/hosts "$RUN_DIR/hosts.orig"

    # Options and time.
    check "Options: view" view options
    reset_step; preset startall-onboot-delay=5
    check "Options: edit start delay" enter startall-onboot-delay
    check "Options: saved" kv_is "/nodes/$NODE/config" startall-onboot-delay 5
    reset_step; preset startall-onboot-delay=""
    check "Options: reset start delay" enter startall-onboot-delay
    check "Time: view" view time
    api_kv "/nodes/$NODE/time"; old=${API_KV[timezone]}
    reset_step; preset timezone=Europe/Paris
    check "Time: set time zone" enter timezone
    check "Time: time zone saved" kv_is "/nodes/$NODE/time" timezone Europe/Paris
    reset_step; preset timezone="$old"
    check "Time: time zone restored" enter timezone
    check "Time: restored" kv_is "/nodes/$NODE/time" timezone "$old"

    # Network: bridge created, applied, removed; revert of pending changes.
    check "Network: view" view network
    reset_step; crud_answers type=bridge; preset iface=vmbr99 cidr=10.97.0.1/24 autostart=1 comments="pvetty test bridge"
    check "Network: add Linux Bridge" key a ""
    view network
    check "Network: pending changes shown" bash -c "[[ '${C_LINES[*]}' == *vmbr99* ]]"
    reset_step; preset comments="edited bridge"
    check "Network: edit bridge" key e "vmbr99|bridge"
    reset_step; check "Network: apply configuration" key A ""
    check "Network: vmbr99 up with its address" wait_for 20 bash -c 'ip -4 addr show vmbr99 | grep -q 10.97.0.1'
    reset_step; crud_answers type=vlan; preset iface=vmbr99.42 comments="pvetty vlan"
    check "Network: add VLAN" key a ""
    reset_step; check "Network: revert pending changes" key X ""
    check "Network: VLAN discarded" api_lacks "/nodes/$NODE/network" iface vmbr99.42
    view network; reset_step
    check "Network: remove bridge" key d "vmbr99|bridge"
    reset_step; check "Network: apply removal" key A ""
    check "Network: vmbr99 removed" wait_for 20 bash -c '! ip link show vmbr99'

    # Updates.
    check "Updates: view" view updates
    reset_step; check "Updates: refresh package database" key R ""
    check "Updates: refresh task OK" task_ok aptupdate
    TERM_CMDS=()
    reset_step; check "Updates: upgrade (terminal)" key u ""

    # Repositories: add the test repository, toggle it, restore the files.
    check "Repositories: view" view repos
    local bk=$RUN_DIR/apt-backup
    mkdir -p "$bk"; cp -a /etc/apt/sources.list /etc/apt/sources.list.d "$bk/" 2>/dev/null
    reset_step; crud_answers handle=test
    check "Repositories: add standard repository (test)" key a ""
    check "Repositories: test repository configured" bash -c "pvesh get /nodes/$NODE/apt/repositories --output-format json | grep -q '\"handle\":\"test\",\"name\":\"Test\",\"status\":1'"
    view repos
    local rk=""; for k in "${C_SELK[@]}"; do [[ $k == repo\|* ]] && rk=$k; done
    reset_step; check "Repositories: toggle a repository" key e "$rk"
    reset_step; check "Repositories: toggle back" key e "$rk"
    rm -rf /etc/apt/sources.list.d; cp -a "$bk/sources.list.d" /etc/apt/; cp -a "$bk/sources.list" /etc/apt/ 2>/dev/null
    check "Repositories: files restored" diff -r "$bk/sources.list.d" /etc/apt/sources.list.d

    # Task history: start a task and stop it.
    check "Task History: view" view tasks
    local upid
    upid=$(pvesh create "/nodes/$NODE/execute" --commands '[{"method":"POST","path":"/nodes/'"$NODE"'/apt/update"}]' 2>/dev/null | grep -o 'UPID:[^"]*' | head -1)
    pvesh get "/nodes/$NODE/tasks" --limit 1 --output-format json > /dev/null
    view tasks
    check "Task History: task log" enter "${C_SELK[0]}"
    # Bulk start: only guests with "start at boot" are started.
    reset_step; answers bulk startall
    TERM_CMDS=()
    CTX_TYPE=node; answers startall
    check "Bulk Actions: start all (onboot guests)" act_node_bulk
}
