# shellcheck shell=bash
# cli.sh - non-interactive subcommands (scripts, cron, AI agents).
#
#   pvetty <command> [arguments] [-o json|table] [--no-wait]
#
# Output: JSON on stdout (default) or a table (-o table, or cli_output = table
# in the configuration). Errors: {"error": "..."} on stderr, exit code 1.
# Commands reuse the API helper of the interface (reads) and pvesh (writes).

CLI_OUTPUT=json
CLI_NOWAIT=0
declare -ga CLI_ARGS=()
declare -gA CLI_OPT=()

cli_usage() {
    cat <<'EOF'
Usage: pvetty <command> [arguments] [options]

Commands:
  nodes list                         nodes of the cluster
  nodes show <node>                  status of a node
  guests list [--node N] [--status S] [--type qemu|lxc] [--tag T]
  guests show <id|name>              status and configuration of a guest
  guests start|shutdown|stop|reboot|suspend|resume <id|name> [--no-wait]
  guests exec <id|name> <command>    run a command (guest agent / pct exec)
  guests ip <id|name>                IP addresses of a guest
  tasks list [--running] [--node N]  recent tasks of the cluster
  tasks log <upid>                   log of a task
  tasks stop <upid>                  stop a running task
  storage list [--node N]            storages
  storage content <node> <storage> [--type iso|vztmpl|backup|images|rootdir]
  api get|create|set|delete <path> [--param value ...]   any API call

Options:
  -o, --output json|table            output format (default: json)
  --no-wait                          return the UPID of a task immediately
  -h, --help                         this help
EOF
}

cli_error() {
    local m=${1//\\/\\\\}; m=${m//\"/\\\"}
    printf '{"error":"%s"}\n' "$m" >&2
    exit 1
}

# Parse "--key value" options and positional arguments.
cli_parse() {
    CLI_ARGS=() CLI_OPT=()
    while (( $# )); do
        case $1 in
            -o|--output) CLI_OUTPUT=$2; shift ;;
            --no-wait) CLI_NOWAIT=1 ;;
            --running) CLI_OPT[running]=1 ;;
            -h|--help) cli_usage; exit 0 ;;
            --*) CLI_OPT[${1#--}]=${2-}; shift ;;
            *) CLI_ARGS+=("$1") ;;
        esac
        shift
    done
}

# Emit TSV rows (API_ROWS-like array name) with the given column names, as
# JSON (numbers kept as numbers) or as an aligned table.
cli_emit() {
    local cols=$1; shift
    if [[ $CLI_OUTPUT == table ]]; then
        { printf '%s\n' "${cols//,/$'\t'}" | tr '[:lower:]' '[:upper:]'; printf '%s\n' "$@"; } | column -t -s $'\t'
    else
        printf '%s\n' "$@" | perl -MJSON -e '
            my @c = split /,/, shift; my @out;
            while (my $l = <STDIN>) { chomp $l; next if $l eq "";
                my @v = split /\t/, $l, -1; my %h;
                for my $i (0 .. $#c) { my $x = $v[$i] // ""; $x =~ s/\x1f/\n/g;
                    $h{$c[$i]} = $x =~ /^-?\d+(\.\d+)?$/ ? $x + 0 : ($x eq "" ? undef : $x) }
                push @out, \%h }
            print JSON->new->canonical->pretty->encode(\@out);' "$cols"
    fi
}

# Raw JSON of an API GET (pretty).
cli_json() {
    api_get json "$1" "${2-}" "" || cli_error "$API_ERR"
    printf '%s' "${API_ROWS[0]}" | perl -MJSON -e 'print JSON->new->canonical->pretty->encode(decode_json(join("", <STDIN>)))'
}

# Resolve a guest from an ID or an exact name: CLI_GID (qemu/100).
cli_guest() {
    local want=$1 id found=""
    for id in "${RES_IDS[@]}"; do
        [[ ${R_TYPE[$id]} == qemu || ${R_TYPE[$id]} == lxc ]] || continue
        if [[ ${R_VMID[$id]} == "$want" || ${R_NAME[$id]} == "$want" ]]; then
            [[ -n $found ]] && cli_error "several guests match '$want' ($found, $id)"
            found=$id
        fi
    done
    [[ -n $found ]] || cli_error "guest '$want' not found"
    CLI_GID=$found
}

# Run a write and print the result; tasks return their UPID / exit status.
cli_write() {
    local cmd=$1 path=$2; shift 2
    local out="$RUN_DIR/cli.out" node=$LOCAL_NODE row upid="" t0 i
    [[ $path =~ ^/nodes/([^/]+) ]] && node=${BASH_REMATCH[1]}
    if (( CLI_NOWAIT )); then
        local -A before=()
        api_get rows "/nodes/$node/tasks" "source=active" "upid" && for row in "${API_ROWS[@]}"; do before[$row]=1; done
        printf -v t0 '%(%s)T' -1
        # pvesh outlives this process (and its run directory): its output
        # goes to a file of its own, removed a minute after the end.
        out=$(mktemp "${TMPDIR:-/tmp}/pvetty-cli.XXXXXX")
        ( setsid bash -c 'pvesh "$@" > "$0" 2>&1 < /dev/null; echo $? > "$0.rc"; sleep 60; rm -f "$0" "$0.rc"' "$out" "$cmd" "$path" "$@" & )
        for (( i = 0; i < 120; i++ )); do
            api_get rows "/nodes/$node/tasks" "source=active" "upid,starttime"
            for row in "${API_ROWS[@]}"; do
                [[ -n ${before[${row%%$'\t'*}]-} ]] && continue
                (( ${row#*$'\t'} >= t0 - 2 )) && { upid=${row%%$'\t'*}; break; }
            done
            [[ -n $upid || -s $out.rc ]] && break
            sleep 0.5
        done
        if [[ -n $upid ]]; then printf '{"upid":"%s"}\n' "$upid"; return 0; fi
        [[ -s $out.rc && $(< "$out.rc") != 0 ]] && cli_error "$(api_error_line "$out")"
        printf '{"result":"done"}\n'
        return 0
    fi
    if pvesh "$cmd" "$path" "$@" --output-format json > "$out" 2>&1; then
        upid=$(grep -m1 -o 'UPID:[^ "]*' "$out")
        if [[ -n $upid ]]; then
            _task_status "$upid"
            printf '{"upid":"%s","status":"%s","exitstatus":"%s"}\n' "$upid" "$TASK_ST" "$TASK_EXIT"
            [[ $TASK_EXIT == OK || $TASK_EXIT == WARNINGS* || -z $TASK_EXIT ]] || exit 1
        else
            local res; res=$(grep -v '^$' "$out" | tail -n 1)
            if [[ $res == \{* || $res == \[* || $res == \"* ]]; then printf '%s\n' "$res"; else printf '{"result":"done"}\n'; fi
        fi
    else
        cli_error "$(api_error_line "$out")"
    fi
}

cli_main() {
    local group=${1-} action=${2-}
    shift 2 2>/dev/null || shift $#
    [[ -n ${CFG[cli_output]-} ]] && CLI_OUTPUT=${CFG[cli_output]}
    cli_parse "$@"
    (( EUID == 0 )) || cli_error "must be run as root on a Proxmox VE node"
    core_init_rundir
    trap 'core_cleanup' EXIT
    spinner_start() { :; }; spinner_stop() { :; }
    TCAP[colors]=8; glyphs_load; i18n_load; theme_load; views_load
    api_start
    res_load || cli_error "cannot read /cluster/resources: $API_ERR"
    local id row
    local -a rows=()
    case $group/$action in
        nodes/list)
            api_get rows /cluster/status "" "type,name,ip,online,level"
            local -A ip=() onl=()
            for row in "${API_ROWS[@]}"; do
                local -a f; tsv_split f "$row"
                [[ ${f[0]} == node ]] && { ip[${f[1]}]=${f[2]}; onl[${f[1]}]=${f[3]}; }
            done
            for id in "${RES_IDS[@]}"; do
                [[ ${R_TYPE[$id]} == node ]] || continue
                local n=${R_NODE[$id]}
                rows+=("$n"$'\t'"${R_STATUS[$id]}"$'\t'"${ip[$n]-}"$'\t'"$(( ${R_CPU[$id]:-0} / 100 ))"$'\t'"${R_MAXCPU[$id]}"$'\t'"${R_MEM[$id]}"$'\t'"${R_MAXMEM[$id]}"$'\t'"${R_UPTIME[$id]}")
            done
            cli_emit "node,status,ip,cpu_percent,cpus,mem,maxmem,uptime" "${rows[@]}" ;;
        nodes/show)
            [[ -n ${CLI_ARGS[0]-} ]] || cli_error "missing node name"
            cli_json "/nodes/${CLI_ARGS[0]}/status" ;;
        guests/list)
            for id in "${RES_IDS[@]}"; do
                [[ ${R_TYPE[$id]} == qemu || ${R_TYPE[$id]} == lxc ]] || continue
                [[ -n ${CLI_OPT[node]-} && ${R_NODE[$id]} != "${CLI_OPT[node]}" ]] && continue
                [[ -n ${CLI_OPT[status]-} && ${R_STATUS[$id]} != "${CLI_OPT[status]}" ]] && continue
                [[ -n ${CLI_OPT[type]-} && ${R_TYPE[$id]} != "${CLI_OPT[type]}" ]] && continue
                [[ -n ${CLI_OPT[tag]-} && ";${R_TAGS[$id]};" != *";${CLI_OPT[tag]};"* ]] && continue
                rows+=("${R_VMID[$id]}"$'\t'"${R_NAME[$id]}"$'\t'"${R_TYPE[$id]}"$'\t'"${R_NODE[$id]}"$'\t'"${R_STATUS[$id]}"$'\t'"$(( ${R_CPU[$id]:-0} / 100 ))"$'\t'"${R_MEM[$id]}"$'\t'"${R_MAXMEM[$id]}"$'\t'"${R_UPTIME[$id]}"$'\t'"${R_TAGS[$id]}"$'\t'"${R_TMPL[$id]:-0}")
            done
            mapfile -t rows < <(printf '%s\n' "${rows[@]}" | sort -n)
            cli_emit "vmid,name,type,node,status,cpu_percent,mem,maxmem,uptime,tags,template" "${rows[@]}" ;;
        guests/show)
            cli_guest "${CLI_ARGS[0]-}"
            local p="/nodes/${R_NODE[$CLI_GID]}/$CLI_GID"
            api_get json "$p/status/current" "" ""; local st=${API_ROWS[0]}
            api_get json "$p/config" "" ""; local cf=${API_ROWS[0]}
            printf '{"id":"%s","node":"%s","status":%s,"config":%s}\n' "$CLI_GID" "${R_NODE[$CLI_GID]}" "$st" "$cf" \
                | perl -MJSON -e 'print JSON->new->canonical->pretty->encode(decode_json(join("", <STDIN>)))' ;;
        guests/start|guests/shutdown|guests/stop|guests/reboot|guests/suspend|guests/resume)
            cli_guest "${CLI_ARGS[0]-}"
            cli_write create "/nodes/${R_NODE[$CLI_GID]}/$CLI_GID/status/$action" ;;
        guests/exec)
            cli_guest "${CLI_ARGS[0]-}"
            local cmd="${CLI_ARGS[*]:1}" node=${R_NODE[$CLI_GID]} vmid=${R_VMID[$CLI_GID]}
            [[ -n $cmd ]] || cli_error "missing command"
            if [[ $CLI_GID == lxc/* ]]; then
                if [[ $node == "$LOCAL_NODE" ]]; then pct exec "$vmid" -- /bin/sh -c "$cmd"; exit $?
                else node_ip "$node"; ssh -o BatchMode=yes "root@$REPLY" pct exec "$vmid" -- /bin/sh -c "$(printf '%q' "$cmd")"; exit $?
                fi
            fi
            local pa="/nodes/$node/qemu/$vmid/agent" pid i
            pid=$(pvesh create "$pa/exec" --command /bin/sh --command -c --command "$cmd" --output-format json 2>"$RUN_DIR/e.err" | perl -MJSON -ne 'print decode_json($_)->{pid}')
            [[ -n $pid ]] || cli_error "$(api_error_line "$RUN_DIR/e.err")"
            for (( i = 0; i < 1200; i++ )); do
                api_kv "$pa/exec-status" "pid=$pid" && [[ ${API_KV[exited]-} == 1 ]] && break
                sleep 0.5
            done
            printf '%s' "${API_KV[out-data]-}" | tr '\037' '\n'
            printf '%s' "${API_KV[err-data]-}" | tr '\037' '\n' >&2
            exit "${API_KV[exitcode]:-1}" ;;
        guests/ip)
            cli_guest "${CLI_ARGS[0]-}"
            guest_ip_cached "$CLI_GID"
            rows=("$CLI_GID"$'\t'"$REPLY")
            cli_emit "id,ip" "${rows[@]}" ;;
        tasks/list)
            api_get rows /cluster/tasks "" "upid,node,type,id,user,starttime,endtime,status" || cli_error "$API_ERR"
            for row in "${API_ROWS[@]}"; do
                local -a f; tsv_split f "$row"
                [[ -n ${CLI_OPT[running]-} && -n ${f[6]-} ]] && continue
                [[ -n ${CLI_OPT[node]-} && ${f[1]} != "${CLI_OPT[node]}" ]] && continue
                rows+=("$row")
            done
            cli_emit "upid,node,type,id,user,starttime,endtime,status" "${rows[@]}" ;;
        tasks/log)
            local upid=${CLI_ARGS[0]-} node
            [[ -n $upid ]] || cli_error "missing UPID"
            node=${upid#UPID:}; node=${node%%:*}
            api_get rows "/nodes/$node/tasks/$upid/log" "limit=100000" "t" || cli_error "$API_ERR"
            printf '%s\n' "${API_ROWS[@]}" ;;
        tasks/stop)
            local upid=${CLI_ARGS[0]-} node
            [[ -n $upid ]] || cli_error "missing UPID"
            node=${upid#UPID:}; node=${node%%:*}
            cli_write delete "/nodes/$node/tasks/$upid" ;;
        storage/list)
            for id in "${RES_IDS[@]}"; do
                [[ ${R_TYPE[$id]} == storage ]] || continue
                [[ -n ${CLI_OPT[node]-} && ${R_NODE[$id]} != "${CLI_OPT[node]}" ]] && continue
                rows+=("${R_STORAGE[$id]}"$'\t'"${R_NODE[$id]}"$'\t'"${R_PLUGIN[$id]}"$'\t'"${R_STATUS[$id]}"$'\t'"${R_CONTENT[$id]}"$'\t'"${R_DISK[$id]}"$'\t'"${R_MAXDISK[$id]}"$'\t'"${R_SHARED[$id]}")
            done
            cli_emit "storage,node,type,status,content,used,total,shared" "${rows[@]}" ;;
        storage/content)
            [[ -n ${CLI_ARGS[1]-} ]] || cli_error "usage: storage content <node> <storage>"
            local q=""; [[ -n ${CLI_OPT[type]-} ]] && q="content=${CLI_OPT[type]}"
            api_get rows "/nodes/${CLI_ARGS[0]}/storage/${CLI_ARGS[1]}/content" "$q" "volid,content,format,size,ctime,vmid,notes" || cli_error "$API_ERR"
            cli_emit "volid,content,format,size,ctime,vmid,notes" "${API_ROWS[@]}" ;;
        api/get)
            local path=${CLI_ARGS[0]-} q="" k
            [[ -n $path ]] || cli_error "missing API path"
            for k in "${!CLI_OPT[@]}"; do urlenc "${CLI_OPT[$k]}"; q+="${q:+&}$k=$REPLY"; done
            cli_json "$path" "$q" ;;
        api/create|api/set|api/delete)
            local path=${CLI_ARGS[0]-} k
            local -a a=()
            [[ -n $path ]] || cli_error "missing API path"
            for k in "${!CLI_OPT[@]}"; do a+=("--$k" "${CLI_OPT[$k]}"); done
            cli_write "$action" "$path" "${a[@]}" ;;
        help/*|/*) cli_usage ;;
        *) cli_usage >&2; exit 2 ;;
    esac
}
