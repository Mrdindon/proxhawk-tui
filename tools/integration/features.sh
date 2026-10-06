# shellcheck shell=bash
# Features of 1.1: action queue, batch actions, search grid filter, run
# command, browser console URL, plugins, key bindings, colours and the
# non-interactive commands, on a test container (TEST_CT2, default 9912).

TEST_CT2=${TEST_CT2:-9912}

ct2_status() { pct status "$TEST_CT2" 2>/dev/null | grep -q "status: $1"; }
# Wait for the actions started by the queue (GBUSY) and report them.
queue_wait() {
    local i id busy
    for (( i = 0; i < 120; i++ )); do
        queue_run
        busy=0
        for id in "${!GBUSY[@]}"; do [[ -s ${GBUSY[$id]}.rc ]] || busy=1; done
        if (( ! busy && ${#GQUEUE[@]} == 0 )); then api_jobs_poll >/dev/null 2>&1; queue_run; return 0; fi
        sleep 1
    done
    return 1
}
cli() { "$PVETTY_HOME/pvetty" "$@"; }
# cli_has <regex> <command...>; "KEY:VALUE" in the regex matches JSON pairs.
cli_has() { local want=${1//\":/\" *: *}; shift; cli "$@" 2>&1 | grep -Eq -- "$want"; }

test_features() {
    local id="lxc/$TEST_CT2" st=${TEST_STORAGE:-VM} br tmpl out upid
    br=$(pvesh get "/nodes/$NODE/network" --type any_bridge --output-format json | grep -o '"iface":"[^"]*"' | head -1 | cut -d'"' -f4)
    tmpl=$(pvesh get "/nodes/$NODE/storage/local/content" --content vztmpl --output-format json | grep -o '"volid":"[^"]*debian[^"]*"' | head -1 | cut -d'"' -f4)
    [[ -n $tmpl ]] || { skip "Features" "no Debian template on 'local'"; return; }
    pct status "$TEST_CT2" >/dev/null 2>&1 && { pct stop "$TEST_CT2" >/dev/null 2>&1; pct destroy "$TEST_CT2" --purge >/dev/null 2>&1; }
    check "Test CT $TEST_CT2 created" pct create "$TEST_CT2" "$tmpl" --hostname pvetty-test-feat --storage "$st" \
        --rootfs "$st:2" --memory 256 --features nesting=1 --net0 "name=eth0,bridge=$br,ip=dhcp" --tags pvetty-test --unprivileged 1
    res_load

    # --- Non-interactive commands -----------------------------------------
    check "CLI: nodes list" cli_has "\"node\":\"$NODE\"" nodes list
    check "CLI: nodes list (table)" cli_has "^NODE" nodes list -o table
    check "CLI: guests list --tag" cli_has "\"vmid\":\"?$TEST_CT2" guests list --tag pvetty-test
    check "CLI: guests show by name" cli_has '"hostname":"pvetty-test-feat"' guests show pvetty-test-feat
    check "CLI: guests start (waits)" cli_has '"exitstatus":"OK"' guests start "$TEST_CT2"
    check "CLI: CT running" ct2_status running
    check "CLI: guests exec" cli_has '^pvetty-exec$' guests exec "$TEST_CT2" 'echo pvetty-exec'
    cli guests exec "$TEST_CT2" 'exit 3' >/dev/null 2>&1
    check "CLI: guests exec exit code" test $? = 3
    check "CLI: guests ip" cli guests ip "$TEST_CT2"
    check "CLI: api set" cli api set "/nodes/$NODE/lxc/$TEST_CT2/config" --description pvetty-cli
    check "CLI: api set verified" kv_is "/nodes/$NODE/lxc/$TEST_CT2/config" description pvetty-cli
    check "CLI: api get" cli_has '"version"' api get /version
    check "CLI: storage list" cli_has '"storage":"local"' storage list
    check "CLI: storage content" cli_has 'vztmpl' storage content "$NODE" local --type vztmpl
    out=$(cli guests show 999999 2>&1); local rc=$?
    check "CLI: unknown guest -> exit 1 + JSON error" test "$rc" = 1 -a "${out#\{\"error\"}" != "$out"
    cli bogus >/dev/null 2>&1
    check "CLI: usage error -> exit 2" test $? = 2
    out=$(cli guests reboot "$TEST_CT2" --no-wait 2>&1)
    upid=$(sed -n 's/.*"upid":"\([^"]*\)".*/\1/p' <<< "$out")
    check "CLI: --no-wait returns the UPID" test -n "$upid"
    check "CLI: tasks log" wait_for 30 cli_has 'TASK OK' tasks log "$upid"
    check "CLI: tasks list" cli_has "$upid" tasks list
    check "CLI: rebooted CT running" wait_for 60 ct2_status running

    # --- Run command / browser console ------------------------------------
    ctx "$id"
    reset_step
    overlay_show() { OVERLAY_TEXT=$(printf '%s\n' "$@"); }
    answers 'echo pvetty-run; exit 4'
    check "Run command (pct exec)" act_run_command
    check "Run command: output" grep -q pvetty-run <<< "${OVERLAY_TEXT-}"
    check "Run command: exit code shown" grep -q 4 <<< "${OVERLAY_TEXT-}"
    unset -f overlay_show; source "$PVETTY_HOME/lib/overlay.sh"
    _web_console_screen() { :; }
    act_web_console > /dev/null
    check "Browser console URL (CT)" grep -q "console=lxc&xtermjs=1&vmid=$TEST_CT2" <<< "$WEB_CONSOLE_URL"
    ctx "node/$NODE"; act_web_console > /dev/null
    check "Browser console URL (node shell)" grep -q "console=shell" <<< "$WEB_CONSOLE_URL"
    unset -f _web_console_screen; source "$PVETTY_HOME/lib/actions.sh"
    NEIGH_CACHE=() ; guest_ip_cached "$id"
    check "IP column: CT address" test -n "$REPLY"

    # --- Queue ---------------------------------------------------------------
    ctx root; reset_step
    PENDING[$id]=external
    queue_add "$id" "CT $TEST_CT2 - Config" set "/nodes/$NODE/lxc/$TEST_CT2/config" --description pvetty-queued
    queue_add "$id" "CT $TEST_CT2 - Config 2" set "/nodes/$NODE/lxc/$TEST_CT2/config" --description pvetty-cancelled
    queue_count; check "Queue: 2 queued" test "$REPLY" = 2
    queue_run
    check "Queue: busy guest waits" test -z "${GBUSY[$id]-}"
    queue_lines
    check "Queue: shown in the Tasks panel" test "${QUEUE_KEYS[1]-}" = "queue|$id|1"
    queue_cancel "$id" 1
    queue_count; check "Queue: cancel" test "$REPLY" = 1
    unset "PENDING[$id]"
    check "Queue: runs when the guest is free" queue_wait
    check "Queue: action done" kv_is "/nodes/$NODE/lxc/$TEST_CT2/config" description pvetty-queued
    # The real api_exec (the test harness replaces it by a synchronous call).
    local saved; saved=$(declare -f api_exec)
    eval "$(sed -n '/^api_exec() {/,/^}/p' "$PVETTY_HOME/lib/api.sh")"
    PENDING[$id]=external; answers yes
    api_exec "CT $TEST_CT2 - Config" set "/nodes/$NODE/lxc/$TEST_CT2/config" --description pvetty-offer
    queue_count; check "Queue: offered for a busy guest" test "$REPLY" = 1
    eval "$saved"
    unset "PENDING[$id]"; queue_wait
    check "Queue: offered action done" kv_is "/nodes/$NODE/lxc/$TEST_CT2/config" description pvetty-offer

    # --- Batch actions and filter -------------------------------------------
    ctx root; res_load
    SELECTED=(); batch_toggle "$id"
    check "Batch: mark" test "${SELECTED[$id]-}" = 1
    reset_step; answers shutdown yes
    check "Batch: shutdown" batch_menu
    check "Batch: queued and run" queue_wait
    check "Batch: CT stopped" wait_for 60 ct2_status stopped
    check "Batch: selection cleared" test "${#SELECTED[@]}" = 0
    reset_step; answers start yes
    check "Batch: start the row guest" batch_menu "$id"
    queue_wait
    check "Batch: CT running" wait_for 60 ct2_status running
    res_load
    GRID_FILTER=([status]=running [type]=lxc [tag]=pvetty-test)
    check "Filter: match" grid_filter_match "$id"
    GRID_FILTER=([status]=stopped)
    check "Filter: no match" eval '! grid_filter_match "$id"'
    GRID_FILTER=()
    ctx root
    check "Datacenter > Search with marks / IP column: view" view search

    # --- Plugins, keys, colours, icons ----------------------------------------
    CFG[plugins]="ansible-inventory community-scripts"
    plugins_load
    ctx root
    check "Plugin ansible-inventory: view" view ansible
    check "Plugin ansible-inventory: guest listed" grep -q "pvetty-test-feat" <<< "$(printf '%s\n' "${ANSIBLE_LINES[@]}")"
    rm -rf "$RUN_DIR/inv"; reset_step; answers "$RUN_DIR/inv/new/dir/inventory.yml"
    check "Plugin ansible-inventory: save (s) to a new directory" key s ""
    check "Plugin ansible-inventory: saved file is valid YAML with the guest" python3 -c "import sys, yaml; d = yaml.safe_load(open(sys.argv[1])); assert 'pvetty-test-feat' in d['all']['hosts']" "$RUN_DIR/inv/new/dir/inventory.yml"
    ctx "node/$NODE"
    check "Plugin community-scripts: menu entry" eval '[[ " ${M_ID[*]} " == *" communityscripts "* ]]'
    CFGX[key.help]="h F1"; keys_load
    check "Keys: rebinding" eval 'key_action h && [[ $REPLY == help ]]'
    unset "CFGX[key.help]"; KEYMAP[help]="F1 ?"; keys_load
    theme_sgr "#ff8800 bold"
    check "Colours: hex + attribute" eval '[[ $REPLY == *1* && $REPLY == *38\;* ]]'
    CFG[icons]=0; glyphs_load
    check "Icons off: menu icons blank" test -z "${G[m_summary]-}"
    CFG[icons]=1; glyphs_load

    # --- Running as another user ---------------------------------------------
    local ro=pvetty-test-ro@pve
    pveum user delete "$ro" >/dev/null 2>&1
    check "User: test user $ro (PVEAuditor)" bash -c "pveum user add $ro && pveum acl modify / --users $ro --roles PVEAuditor"
    check "User: read as $ro" cli_has '"node"' nodes list --user "$ro"
    out=$(cli api set "/nodes/$NODE/lxc/$TEST_CT2/config" --description pvetty-ro --user "$ro" 2>&1)
    check "User: write refused for $ro" grep -q "Permission check failed" <<< "$out"
    check "User: write not done" eval '! kv_is "/nodes/$NODE/lxc/$TEST_CT2/config" description pvetty-ro'
    check "User: console refused for $ro" eval '! PVETTY_USER=$ro perl "$PVETTY_HOME/lib/broker.pl" --once perm "/vms/$TEST_CT2" "priv=VM.Console" "" | grep -qx 1'
    check "User: test user removed" pveum user delete "$ro"
    # A user with the rights on the container: the same write is allowed.
    local adm=pvetty-test-vmadm@pve
    pveum user delete "$adm" >/dev/null 2>&1
    check "User: test user $adm (PVEVMAdmin on the CT)" bash -c "pveum user add $adm && pveum acl modify /vms/$TEST_CT2 --users $adm --roles PVEVMAdmin"
    check "User: write allowed for $adm" cli api set "/nodes/$NODE/lxc/$TEST_CT2/config" --description pvetty-vmadm --user "$adm"
    check "User: write done" kv_is "/nodes/$NODE/lxc/$TEST_CT2/config" description pvetty-vmadm
    check "User: test user removed" pveum user delete "$adm"

    # --- Clean up ---------------------------------------------------------------
    pct stop "$TEST_CT2" >/dev/null 2>&1
    check "Test CT $TEST_CT2 removed" pct destroy "$TEST_CT2" --purge
    res_load
}
