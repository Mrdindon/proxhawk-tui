# shellcheck shell=bash
# taskviewer.sh - "Task viewer" window, as in the web UI: it opens over the
# interface when a task is started (and on a task of the task lists), takes
# the focus, follows the output live, offers Stop while the task runs, stays
# open when the task ends, and the panels are refreshed when it is closed.
#
#   task_viewer <upid> [title]
#
# Keys: Tab / ← → switch Output / Status, ↑ ↓ PgUp PgDn Home End scroll,
#       x stop the task, Esc / q / Enter close. Mouse: wheel, buttons.

declare -ga TV_LOG=() TV_STAT=()
TV_TAB=output TV_SCROLL=0 TV_FOLLOW=1

task_viewer() {
    local upid=$1 title=${2:-} node
    node=${upid#UPID:}; node=${node%%:*}
    if [[ -z $title ]]; then
        local -a p; IFS=: read -r -a p <<< "$upid"
        task_desc "${p[5]-}" "${p[6]-}"; title=$REPLY
    fi
    TV_LOG=() TV_STAT=() TV_TAB=output TV_SCROLL=0 TV_FOLLOW=1
    local st="" exitst="" last_poll=0 done=0 key
    local -a hr=() hc1=() hc2=() ha=()

    _tv_poll() {
        local row
        # New log lines only (the API numbers them from 1).
        if api_get rows "/nodes/$node/tasks/$upid/log" "start=${#TV_LOG[@]}&limit=5000" "n,t"; then
            for row in "${API_ROWS[@]}"; do TV_LOG+=("${row#*$'\t'}"); done
        fi
        if api_get kv "/nodes/$node/tasks/$upid/status"; then
            TV_STAT=("${API_ROWS[@]}")
            for row in "${API_ROWS[@]}"; do
                case ${row%%$'\t'*} in
                    status) st=${row#*$'\t'} ;;
                    exitstatus) exitst=${row#*$'\t'} ;;
                esac
            done
        fi
        [[ $st == stopped ]] && done=1
    }

    _tv_draw() {
        local bw=$(( COLS - 6 )) bh=$(( ROWS - 4 )) top=3 left r i line n body
        (( bw > 160 )) && bw=160
        left=$(( (COLS - bw) / 2 + 1 ))
        body=$(( bh - 6 ))
        FRAME=""
        hr=() hc1=() hc2=() ha=()
        T "Task viewer"; local t="$REPLY: $title"
        _hline "$top" "$left" "$bw" "${G[tl]}" "${G[tr]}" "$t" "${C[accent]}"
        # Tabs and state.
        local t1 t2 state
        T "Output"; t1=$REPLY; T "Status"; t2=$REPLY
        if [[ $TV_TAB == output ]]; then t1="${C[sel]} $t1 ${C[norm]}"; t2="${C[btn]} $t2 ${C[norm]}"
        else t1="${C[btn]} $t1 ${C[norm]}"; t2="${C[sel]} $t2 ${C[norm]}"
        fi
        if (( done )); then
            if [[ $exitst == OK ]]; then state="${C[ok]}${G[st_ok]} OK${C[norm]}"
            elif [[ $exitst == WARNINGS* ]]; then state="${C[warn]}! $exitst${C[norm]}"
            else state="${C[err]}${G[st_err]} ${exitst:-error}${C[norm]}"
            fi
        else
            T "running"; state="${C[info]}${SPIN_MARK} $REPLY${C[norm]}"
        fi
        vlen "$state"; local sw=$REPLY
        line=" $t1 $t2"
        fit "$line" $(( bw - 4 - sw )); line="$REPLY$state"
        fit "$line" $(( bw - 3 ))
        _put $(( top + 1 )) "$left" "${C[border]}${G[v]}${C[norm]} ${REPLY}${C[border]}${G[v]}${C[norm]}"
        hr+=($(( top + 1 ))); hc1+=($(( left + 2 ))); hc2+=($(( left + 2 + ${#t1} ))); ha+=(tab)
        repeat "${G[h]}" $(( bw - 2 ))
        _put $(( top + 2 )) "$left" "${C[border]}${G[tee_l]}${REPLY}${G[tee_r]}${C[norm]}"
        # Body.
        local -a lines
        if [[ $TV_TAB == output ]]; then lines=("${TV_LOG[@]}")
        else
            for line in "${TV_STAT[@]}"; do
                local k=${line%%$'\t'*} v=${line#*$'\t'}
                [[ $k == starttime ]] && { fmt_time "$v"; v=$REPLY; }
                printf -v line '%-12s %s' "$k" "$v"; lines+=("$line")
            done
        fi
        n=${#lines[@]}
        (( TV_FOLLOW )) && TV_SCROLL=$(( n - body ))
        (( TV_SCROLL > n - body )) && TV_SCROLL=$(( n - body ))
        (( TV_SCROLL < 0 )) && TV_SCROLL=0
        for (( r = 0; r < body; r++ )); do
            i=$(( TV_SCROLL + r ))
            fit "${lines[i]-}" $(( bw - 4 ))
            _put $(( top + 3 + r )) "$left" "${C[border]}${G[v]}${C[norm]} ${REPLY} ${C[border]}${G[v]}${C[norm]}"
        done
        repeat "${G[h]}" $(( bw - 2 ))
        _put $(( top + 3 + body )) "$left" "${C[border]}${G[tee_l]}${REPLY}${G[tee_r]}${C[norm]}"
        # Buttons.
        local b1 b2 info x
        T "Stop"; b1=" ${G[btn_stop]} $REPLY x "
        T "Close"; b2=" $REPLY Esc "
        if (( n )); then Tf "Lines %d-%d of %d" $(( TV_SCROLL + 1 )) $(( TV_SCROLL + (n < body ? n : body) )) "$n"; else REPLY=""; fi
        info=" ${C[dim]}${REPLY}${C[norm]}"
        (( TV_FOLLOW )) && { T "following"; info+=" ${C[dim]}($REPLY)${C[norm]}"; }
        fit "$info" $(( bw - 6 - ${#b1} - ${#b2} ))
        line="$REPLY"
        if (( done )); then line+="${C[btn_dis]}${b1}${C[norm]} "; else line+="${C[btn]}${b1}${C[norm]} "; fi
        line+="${C[btn]}${b2}${C[norm]}"
        _put $(( top + 4 + body )) "$left" "${C[border]}${G[v]}${C[norm]} ${line} ${C[border]}${G[v]}${C[norm]}"
        x=$(( left + bw - 2 - ${#b2} ))
        hr+=($(( top + 4 + body ))); hc1+=("$x"); hc2+=($(( x + ${#b2} - 1 ))); ha+=(close)
        x=$(( x - 1 - ${#b1} ))
        hr+=($(( top + 4 + body ))); hc1+=("$x"); hc2+=($(( x + ${#b1} - 1 ))); ha+=(stop)
        _hline $(( top + 5 + body )) "$left" "$bw" "${G[bl]}" "${G[br]}"
        FRAME=${FRAME//"$SPIN_MARK"/${SPINNER[SPIN_FRAME % ${#SPINNER[@]}]}}
        printf '%s' "$FRAME"
        TV_BODY=$body
    }

    _tv_stop() {
        (( done )) && return
        T "Stop this task?"
        if dlg_yesno "Task viewer" "$REPLY"; then
            pvesh delete "/nodes/$node/tasks/$upid" > /dev/null 2>&1
        fi
        draw
    }

    draw            # the interface stays visible around the window
    _tv_poll
    while :; do
        _tv_draw
        if read_key 0.3; then
            case $KEY in
                ESC|q|ENTER) break ;;
                TAB|LEFT|RIGHT) [[ $TV_TAB == output ]] && TV_TAB=status || TV_TAB=output; TV_SCROLL=0; TV_FOLLOW=$([[ $TV_TAB == output ]] && echo 1 || echo 0) ;;
                UP|k) (( TV_SCROLL-- )); TV_FOLLOW=0 ;;
                DOWN|j) (( TV_SCROLL++ )); TV_FOLLOW=0 ;;
                PGUP) (( TV_SCROLL -= TV_BODY - 1 )); TV_FOLLOW=0 ;;
                PGDN) (( TV_SCROLL += TV_BODY - 1 )); TV_FOLLOW=0 ;;
                HOME|g) TV_SCROLL=0; TV_FOLLOW=0 ;;
                END|G) TV_FOLLOW=1 ;;
                x) _tv_stop ;;
                MOUSE)
                    if (( MOUSE_B == 64 )); then (( TV_SCROLL -= 3 )); TV_FOLLOW=0
                    elif (( MOUSE_B == 65 )); then (( TV_SCROLL += 3 ))
                    elif (( MOUSE_B == 0 && ! MOUSE_REL )); then
                        local hi
                        for hi in "${!hr[@]}"; do
                            (( MOUSE_Y == hr[hi] && MOUSE_X >= hc1[hi] && MOUSE_X <= hc2[hi] )) || continue
                            case ${ha[hi]} in
                                close) break 2 ;;
                                stop) _tv_stop ;;
                                tab) [[ $TV_TAB == output ]] && TV_TAB=status || TV_TAB=output ;;
                            esac
                        done
                    fi ;;
            esac
            (( TV_SCROLL < 0 )) && TV_SCROLL=0
            continue
        fi
        (( SPIN_FRAME++ ))
        if (( ! done )); then
            now
            (( NOW != last_poll )) && { _tv_poll; last_poll=$NOW; }
        fi
        (( NEED_RESIZE )) && { NEED_RESIZE=0; layout_compute; draw; }
    done

    # A task still running when the window is closed is followed in the footer.
    (( done )) || TASK_WATCH[$upid]=$title
    if (( done )); then _task_report_status "$title" "$exitst"; fi
    # Like the web UI: the panels behind the window are refreshed.
    api_cache_clear
    if declare -F refresh_all >/dev/null; then refresh_all 1; else content_load 1; fi
    NEED_REDRAW=1
}

_task_report_status() {
    if [[ $2 == OK || $2 == WARNINGS* ]]; then Tf "%s: finished (%s)" "$1" "$2"; status_msg ok "$REPLY"
    else Tf "%s: failed - %s" "$1" "$2"; status_msg err "$REPLY"
    fi
}
