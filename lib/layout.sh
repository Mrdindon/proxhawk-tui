# shellcheck shell=bash
# layout.sh - screen geometry and drawing. The whole frame is composed in a
# single string (FRAME) and written at once to avoid flickering.
#
#  ┌ header: logo, version, search, Documentation, Create VM/CT, user ───────┐
#  │ resource tree │ title ..................................... toolbar  │
#  │               ├──────────────┬────────────────────────────────────────┤
#  │               │ menu         │ content                                │
#  ├ tasks / cluster log ──────────────────────────────────────────────────┤
#  └ footer: key hints / status messages ──────────────────────────────────┘

FOCUS=tree               # tree | menu | content | tasks
FOCI=(tree menu content tasks)
FRAME=""
TW=28 MW=22 MAIN_H=10 TASK_H=0 MAIN_TOP=2
TREE_H=5 MENU_H=5 TASK_ROWS=0
CX=0 CY=0                 # top-left cell of the content area
MENU_X=0
STATUS_MSG="" STATUS_LVL=info STATUS_T=0
PVE_VERSION=""
declare -ga HIT_R=() HIT_C1=() HIT_C2=() HIT_ACT=()

status_msg() { STATUS_LVL=$1 STATUS_MSG=$2; printf -v STATUS_T '%(%s)T' -1; NEED_REDRAW=1; }

_put() { FRAME+=$'\e['"$1;$2H$3"; }
_hit() { HIT_R+=("$1"); HIT_C1+=("$2"); HIT_C2+=("$3"); HIT_ACT+=("$4"); }

layout_compute() {
    term_size
    TW=${CFG[tree_width]}
    if (( TW <= 0 )); then
        TW=$(( COLS * 22 / 100 ))
        (( TW < 24 )) && TW=24
        (( TW > 40 )) && TW=40
    fi
    MW=24
    (( COLS < 110 )) && MW=20
    (( COLS < 90 )) && MW=16
    TASK_ROWS=${CFG[task_rows]}
    (( ROWS < 26 && TASK_ROWS > 3 )) && TASK_ROWS=3
    (( ROWS < 20 )) && TASK_ROWS=0
    TASK_H=0
    (( TASK_ROWS > 0 )) && TASK_H=$(( TASK_ROWS + 3 ))
    MAIN_TOP=2
    MAIN_H=$(( ROWS - 2 - TASK_H ))   # rows of the tree/content boxes
    TREE_H=$(( MAIN_H - 2 ))
    MENU_H=$(( MAIN_H - 4 ))
    MENU_X=$(( TW + 2 ))
    CX=$(( TW + MW + 4 ))       # one blank column after the menu separator
    CY=$(( MAIN_TOP + 3 ))
    CONTENT_W=$(( COLS - CX - 1 ))
    CONTENT_H=$(( MAIN_H - 4 ))
    (( CONTENT_W < 20 )) && CONTENT_W=20
}

# Horizontal border with an optional title: _hline <row> <col> <width> <left> <right> [title] [colour]
_hline() {
    # shellcheck disable=SC2318  # C[title] is an array key, not the local "title"
    local r=$1 c=$2 w=$3 lch=$4 rch=$5 title=${6:-} tcol=${7:-${C[title]}} t=""
    if [[ -n $title ]]; then
        t=" $title "
        vlen "$t"
        repeat "${G[h]}" $(( w - 2 - REPLY - 1 ))
        _put "$r" "$c" "${C[border]}${lch}${G[h]}${tcol}${t}${C[border]}${REPLY}${rch}${C[norm]}"
    else
        repeat "${G[h]}" $(( w - 2 ))
        _put "$r" "$c" "${C[border]}${lch}${REPLY}${rch}${C[norm]}"
    fi
}

_focus_col() { if [[ $FOCUS == "$1" ]]; then REPLY=${C[accent]}; else REPLY=${C[title]}; fi; }

draw() {
    FRAME=$'\e[0m'"${C[norm]}"
    HIT_R=() HIT_C1=() HIT_C2=() HIT_ACT=()
    if (( COLS < 80 || ROWS < 18 )); then
        Tf "Terminal too small (%sx%s) - minimum is 80x18" "$COLS" "$ROWS"
        FRAME+=$'\e[2J\e[1;1H'"$REPLY"
        (( ${#CONSOLE_SUBST[@]} )) && frame_fix
        printf '%s' "$FRAME"
        return
    fi
    draw_header
    draw_tree
    draw_content_box
    (( TASK_H > 0 )) && draw_tasks
    draw_footer
    # Animate the "running" markers (tasks panel, task history, footer).
    if [[ $FRAME == *"$SPIN_MARK"* ]]; then
        SPIN_ACTIVE=1
        FRAME=${FRAME//"$SPIN_MARK"/${SPINNER[SPIN_FRAME % ${#SPINNER[@]}]}}
    else
        SPIN_ACTIVE=0
    fi
    (( ${#CONSOLE_SUBST[@]} )) && frame_fix
    printf '%s' "$FRAME"
    NEED_REDRAW=0
}

# ---------------------------------------------------------------------------
draw_header() {
    local left right x i label
    left=" ${C[logo]}PROXMOX${C[header]} Virtual Environment ${C[header_dim]}${PVE_VERSION}${C[header]}"
    T "Search"; local search=" ${G[search]} $REPLY (/) "
    # Right side buttons: Documentation, Create VM, Create CT, user menu,
    # with their keyboard shortcut (function keys, shown in each button).
    local -a bl=() bk=() ba=()
    T "Documentation"; bl+=("${G[docs]} $REPLY"); bk+=(F1); ba+=(help)
    T "Create VM"; bl+=("${G[qemu]} $REPLY"); bk+=(F2); ba+=(create_vm)
    T "Create CT"; bl+=("${G[lxc]} $REPLY"); bk+=(F3); ba+=(create_ct)
    bl+=("${G[user]} ${PVE_USER:-root@pam} ${G[caret]}"); bk+=(F4); ba+=(user_menu)
    local w=0 sw lbw tw
    for i in "${!bl[@]}"; do dwidth "${bl[i]}"; (( w += REPLY + ${#bk[i]} + 4 )); done
    # Not enough room next to the title (the search box goes first): keep
    # only the icons of the header buttons.
    vlen "$left"; tw=$REPLY
    if (( COLS - w < tw + 2 )); then
        w=0
        for i in "${!bl[@]}"; do
            [[ ${ba[i]} == user_menu ]] || bl[i]=${bl[i]%% *}
            dwidth "${bl[i]}"; (( w += REPLY + ${#bk[i]} + 4 ))
        done
    fi
    x=$(( COLS - w + 1 ))
    vlen "$left"; local lw=$REPLY
    fit "$left" $(( COLS ))
    _put 1 1 "${C[header]}${REPLY}"
    # Search box in the middle when there is room.
    dwidth "$search"; sw=$REPLY
    if (( x - lw > sw + 4 )); then
        local sx=$(( lw + (x - lw - sw) / 2 ))
        _put 1 "$sx" "${C[btn]}${search}${C[header]}"
        _hit 1 "$sx" $(( sx + sw )) "search"
    fi
    for i in "${!bl[@]}"; do
        label=" ${bl[i]} ${bk[i]} "; dwidth "$label"; lbw=$REPLY
        _put 1 "$x" "${C[btn]} ${bl[i]} ${C[btn_key]}${bk[i]}${C[btn]} ${C[header]} "
        _hit 1 "$x" $(( x + lbw )) "${ba[i]}"
        (( x += lbw + 1 ))
    done
    FRAME+="${C[norm]}"
}

# ---------------------------------------------------------------------------
draw_tree() {
    local r i idx id depth line plain exp icon n=${#TV_IDX[@]} sel w=$(( TW - 2 ))
    _focus_col tree
    tree_view_label
    _hline "$MAIN_TOP" 1 "$TW" "${G[tl]}" "${G[tr]}" "$REPLY ${G[caret]}" "${C[title]}"
    _hit "$MAIN_TOP" 2 "$TW" "treeview"
    # Keep the cursor visible.
    (( TREE_CUR < TREE_SCROLL )) && TREE_SCROLL=$TREE_CUR
    (( TREE_CUR >= TREE_SCROLL + TREE_H )) && TREE_SCROLL=$(( TREE_CUR - TREE_H + 1 ))
    for (( r = 0; r < TREE_H; r++ )); do
        i=$(( TREE_SCROLL + r ))
        line=""
        if (( i < n )); then
            idx=${TV_IDX[i]} id=${TREE_ID[idx]} depth=${TREE_DEPTH[idx]}
            printf -v line '%*s' $(( depth * 2 )) ""
            if [[ -n ${TREE_KIDS[$idx]-} ]]; then
                [[ -n ${COLLAPSED[$id]-} ]] && exp=${G[exp_closed]} || exp=${G[exp_open]}
            else
                exp=" "
            fi
            if [[ $id == root ]]; then
                T "Datacenter"; label=$REPLY
                [[ -n $CLUSTER_NAME ]] && label+=" ($CLUSTER_NAME)"
                icon="${C[norm]}${G[dc]}"
            elif [[ $id == folder/* ]]; then
                label=${FOLDER_LABEL[${id#folder/}]-$id}
                icon="${C[norm]}${G[folder]}"
            else
                res_label "$id"; label=$REPLY
                res_icon "$id"; icon=$REPLY
            fi
            line+="${C[dim]}${exp}${C[norm]} ${icon}${C[norm]} ${label}"
            [[ -n ${R_LOCK[$id]-} ]] && line+=" ${C[warn]}${G[lock]}${C[norm]}"
            [[ -n ${PENDING[$id]-} ]] && line+=" ${C[warn]}${SPIN_MARK}${C[norm]}"
            if [[ ${CFG[show_tags]} == 1 && -n ${R_TAGS[$id]-} ]]; then
                local tg
                for tg in ${R_TAGS[$id]//;/ }; do line+=" ${C[tag]}${tg}${C[norm]}"; done
            fi
            if (( i == TREE_CUR )); then
                strip "$line"; plain=$REPLY
                fit "$plain" "$w"
                [[ $FOCUS == tree ]] && sel=${C[sel]} || sel=${C[sel_inactive]}
                line="${sel}${REPLY}${C[norm]}"
            else
                fit "$line" "$w"; line=$REPLY
            fi
        else
            printf -v line '%*s' "$w" ""
        fi
        _put $(( MAIN_TOP + 1 + r )) 1 "${C[border]}${G[v]}${C[norm]}${line}${C[border]}${G[v]}"
    done
    _hline $(( MAIN_TOP + MAIN_H - 1 )) 1 "$TW" "${G[bl]}" "${G[br]}"
}

# ---------------------------------------------------------------------------
draw_content_box() {
    local x0=$(( TW + 1 )) w=$(( COLS - TW )) r i line sel title tb="" tbw=0
    # Top border, title and toolbar.
    _hline "$MAIN_TOP" "$x0" "$w" "${G[tl]}" "${G[tr]}"
    ctx_title; title=$REPLY
    toolbar_load
    local -a bx=()
    _toolbar_build 0
    # Not enough room: compact buttons (icon + hot key only).
    (( w - 4 - tbw < 24 )) && _toolbar_build 1
    local tw=$(( w - 4 - tbw ))
    (( tw < 10 )) && { tb=""; tbw=0; bx=(); tw=$(( w - 4 )); }
    fit "${C[title]}${title}${C[norm]}" "$tw"
    _put $(( MAIN_TOP + 1 )) "$x0" "${C[border]}${G[v]}${C[norm]} ${REPLY}${tb}"
    _put $(( MAIN_TOP + 1 )) "$COLS" "${C[border]}${G[v]}"
    # Register toolbar hit boxes.
    local bxp=$(( x0 + 2 + tw ))
    for i in "${!bx[@]}"; do
        _hit $(( MAIN_TOP + 1 )) "$bxp" $(( bxp + bx[i] - 1 )) "tb:$i"
        (( bxp += bx[i] + 1 ))
    done
    # Separator between title and body.
    repeat "${G[h]}" "$MW"; local mline=$REPLY
    repeat "${G[h]}" $(( w - MW - 3 ))
    _put $(( MAIN_TOP + 2 )) "$x0" "${C[border]}${G[tee_l]}${mline}${G[tee_t]}${REPLY}${G[tee_r]}${C[norm]}"

    # Menu column.
    (( MENU_CUR < MENU_SCROLL )) && MENU_SCROLL=$MENU_CUR
    (( MENU_CUR >= MENU_SCROLL + MENU_H )) && MENU_SCROLL=$(( MENU_CUR - MENU_H + 1 ))
    for (( r = 0; r < MENU_H; r++ )); do
        i=$(( MENU_SCROLL + r ))
        line=""
        if (( i < ${#M_ID[@]} )); then
            printf -v line '%*s' $(( M_LVL[i] * 2 )) ""
            local ic=${G[${M_ICON[i]}]-}
            [[ -n $ic ]] && line+="${C[menu_icon]}${ic}${C[norm]} "
            T "${M_LABEL[i]}"; line+=$REPLY
            if (( i == MENU_CUR )); then
                [[ $FOCUS == menu ]] && sel=${C[sel]} || sel=${C[sel_inactive]}
                strip "$line"; fit " $REPLY" "$MW"; line="${sel}${REPLY}${C[norm]}"
            else
                fit " $line" "$MW"; line=$REPLY
            fi
        else
            printf -v line '%*s' "$MW" ""
        fi
        _put $(( CY + r )) "$x0" "${C[border]}${G[v]}${C[norm]}${line}${C[border]}${G[v]}${C[norm]}"
    done

    # Panel button bar (pinned above the content).
    local cy=$CY ch=$CONTENT_H
    if (( ${#PB_KEYS[@]} )); then
        local bar="" bx2=$(( CX )) lab key icon
        for i in "${!PB_KEYS[@]}"; do
            key=${PB_KEYS[i]}; T "${PB_LABELS[i]//_/ }"; lab=$REPLY
            case $key in a) icon="${G[btn_create]} " ;; e) icon="${G[btn_edit]} " ;; d) icon="${G[btn_remove]} " ;; *) icon="" ;; esac
            [[ $key == ENTER || $key == Enter ]] && key="⏎"
            (( UTF8 )) || [[ $key != "⏎" ]] || key="Enter"
            local plain=" ${icon}${lab} ${key} " pw
            dwidth "$plain"; pw=$REPLY
            (( bx2 + pw > COLS - 1 )) && break
            bar+="${C[btn]} ${icon}${lab} ${C[btn_key]}${key}${C[btn]} ${C[norm]} "
            _hit "$cy" "$bx2" $(( bx2 + pw - 1 )) "ckey:${PB_KEYS[i]}"
            (( bx2 += pw + 1 ))
        done
        fit "$bar" "$CONTENT_W"
        _put "$cy" $(( CX - 1 )) " ${REPLY}${C[norm]} "
        _put "$cy" "$COLS" "${C[border]}${G[v]}${C[norm]}"
        (( cy++, ch-- ))
    fi
    CONTENT_Y=$cy CONTENT_VH=$ch

    # Content area.
    local n=${#C_LINES[@]} selline=-1
    (( ${#C_SELL[@]} )) && selline=${C_SELL[C_CUR]-0}
    if (( selline >= 0 )); then
        (( selline < C_SCROLL )) && C_SCROLL=$selline
        (( selline >= C_SCROLL + ch )) && C_SCROLL=$(( selline - ch + 1 ))
    fi
    (( C_SCROLL > n - ch )) && C_SCROLL=$(( n - ch ))
    (( C_SCROLL < 0 )) && C_SCROLL=0
    # Scrollbar thumb on the right border.
    local th=0 tp=-1
    if (( n > ch )); then
        th=$(( ch * ch / n )); (( th < 1 )) && th=1
        tp=$(( C_SCROLL * (ch - th) / (n - ch) ))
    fi
    for (( r = 0; r < ch; r++ )); do
        i=$(( C_SCROLL + r ))
        line=${C_LINES[i]-}
        if (( i == selline )); then
            [[ $FOCUS == content ]] && sel=${C[sel]} || sel=${C[sel_inactive]}
            strip "$line"; fit "$REPLY" "$CONTENT_W"
            line="${sel}${REPLY}${C[norm]}"
        else
            fit "$line" "$CONTENT_W"; line="${REPLY}${C[norm]}"
        fi
        _put $(( cy + r )) $(( CX - 1 )) " ${line} "
        if (( tp >= 0 && r >= tp && r < tp + th )); then
            _put $(( cy + r )) "$COLS" "${C[accent]}${G[scroll]}${C[norm]}"
        else
            _put $(( cy + r )) "$COLS" "${C[border]}${G[v]}${C[norm]}"
        fi
    done
    repeat "${G[h]}" "$MW"; mline=$REPLY
    repeat "${G[h]}" $(( w - MW - 3 ))
    _put $(( MAIN_TOP + MAIN_H - 1 )) "$x0" "${C[border]}${G[bl]}${mline}${G[tee_b]}${REPLY}${G[br]}${C[norm]}"
}

# Build the toolbar string (tb, tbw, bx[]); _toolbar_build <compact 0|1>
_toolbar_build() {
    local compact=$1 i lab k pre post btn lk ll pos
    tb="" tbw=0 bx=()
    for i in "${!TB_KEY[@]}"; do
        T "${TB_LABEL[i]}"
        lab=$REPLY k=${TB_KEY[i]} pos=-1
        if (( compact )); then
            pre="" post="" lab=""
        else
            # Underline the hot key inside the label when present (any case).
            lk=${k,,} ll=${lab,,}
            if [[ ${#k} == 1 && $k == "$lk" && $ll == *"$lk"* ]]; then
                pre=${ll%%"$lk"*}; pos=${#pre}
            elif [[ ${#k} == 1 && $lab == *"$k"* ]]; then
                pre=${lab%%"$k"*}; pos=${#pre}
            fi
            if (( pos >= 0 )); then
                pre=${lab:0:pos} k=${lab:pos:1} post=${lab:pos+1}
            else
                pre="$lab (" post=")"
            fi
        fi
        if [[ ${TB_ON[i]} == 1 ]]; then
            btn="${C[btn]} ${TB_ICON[i]:+${TB_ICON[i]} }${pre}${C[btn_key]}${k}${C[btn]}${post} ${C[norm]}"
        else
            btn="${C[btn_dis]} ${TB_ICON[i]:+${TB_ICON[i]} }${pre}${k}${post} ${C[norm]}"
        fi
        vlen "$btn"; bx+=("$REPLY")
        tb+="$btn "
        (( tbw += REPLY + 1 ))
    done
}

# ---------------------------------------------------------------------------
draw_tasks() {
    local top=$(( MAIN_TOP + MAIN_H )) r i line sel t1 t2 w=$(( COLS - 2 ))
    T "Tasks"; t1=$REPLY
    T "Cluster log"; t2=$REPLY
    if [[ $TASK_TAB == tasks ]]; then
        t1="${C[accent]}${t1}${C[border]}"; t2="${C[dim]}${t2}${C[border]}"
    else
        t1="${C[dim]}${t1}${C[border]}"; t2="${C[accent]}${t2}${C[border]}"
    fi
    [[ $FOCUS == tasks ]] && t1="${C[title]}${G[caret]}${C[border]} $t1"
    _hline "$top" 1 "$COLS" "${G[tl]}" "${G[tr]}" "${t1} ${G[vsep]} ${t2}" "${C[title]}"
    _hit "$top" 2 30 "tasktab"
    tasks_header; fit " $REPLY" "$w"
    _put $(( top + 1 )) 1 "${C[border]}${G[v]}${C[th]}${REPLY}${C[border]}${G[v]}${C[norm]}"
    (( TASK_CUR < TASK_SCROLL )) && TASK_SCROLL=$TASK_CUR
    (( TASK_CUR >= TASK_SCROLL + TASK_ROWS )) && TASK_SCROLL=$(( TASK_CUR - TASK_ROWS + 1 ))
    for (( r = 0; r < TASK_ROWS; r++ )); do
        i=$(( TASK_SCROLL + r ))
        line=""
        (( i < ${#TASK_LINES[@]} )) && line=${TASK_LINES[i]}
        if (( i == TASK_CUR && i < ${#TASK_LINES[@]} )) && [[ $FOCUS == tasks ]]; then
            strip "$line"; fit " $REPLY" "$w"; line="${C[sel]}${REPLY}${C[norm]}"
        else
            fit " $line" "$w"; line="${REPLY}${C[norm]}"
        fi
        _put $(( top + 2 + r )) 1 "${C[border]}${G[v]}${C[norm]}${line}${C[border]}${G[v]}"
    done
    _hline $(( top + 2 + TASK_ROWS )) 1 "$COLS" "${G[bl]}" "${G[br]}"
}

# ---------------------------------------------------------------------------
draw_footer() {
    local line="" age NOW
    now
    age=$(( NOW - STATUS_T ))
    if [[ -n $STATUS_MSG ]] && (( age < 8 )); then
        local col=${C[footer]} g=${G[bullet]}
        case $STATUS_LVL in
            ok) g=${G[st_ok]} ;;
            err) g=${G[st_err]} ;;
            warn) g="!" ;;
        esac
        line="${C[footer_key]} $g ${C[footer]}${STATUS_MSG}"
    else
        local -a hints=("${KEYMAP[help]%% *}:Help" "Tab:Panel" "${KEYMAP[search]%% *}:Search")
        case $FOCUS in
            tree) hints+=("Space:Expand" "v:View") ;;
            tasks) hints+=("Enter:Log" "x:Stop/Cancel" "l:Tasks/Log") ;;
            content)
                local vh=${VIEW_HINT[$VIEW_FN]-}
                if crud_has "$VIEW_FN"; then crud_hints "$VIEW_FN"; vh="$REPLY $vh"; fi
                read -r -a _vh <<< "$vh"
                hints+=("${_vh[@]}") ;;
        esac
        hints+=("${KEYMAP[refresh]%% *}:Refresh" "${KEYMAP[quit]%% *}:Quit")
        local h k lab
        for h in "${hints[@]}"; do
            k=${h%%:*} lab=${h#*:}
            T "${lab//_/ }"
            line+="${C[footer_key]} $k ${C[footer]}$REPLY "
        done
        local nj=$(( ${#JOBS[@]} + ${#TASK_WATCH[@]} + ${#BG_CMDS[@]} ))
        (( nj )) && { Tf "%d running job(s)" "$nj"; line+=" ${C[footer_key]}${SPIN_MARK}${C[footer]} $REPLY"; }
    fi
    # Right side: automatic refresh countdown (or paused).
    local ar=""
    if (( ${CFG[refresh]:-0} > 0 )); then
        if (( ${AUTO_REFRESH:-1} )); then
            local left=$(( CFG[refresh] - (NOW - LAST_REFRESH) )); (( left < 0 )) && left=0
            ar=" ${G[refresh]:-↻} ${left}s "
        else
            T "auto-refresh paused"; ar=" ‖ $REPLY (${KEYMAP[auto_refresh]%% *}) "
        fi
    fi
    vlen "$ar"; local arw=$REPLY
    fit "$line" $(( COLS - arw ))
    _put "$ROWS" 1 "${C[footer]}${REPLY}${C[footer_key]}${ar}${C[norm]}"
}
