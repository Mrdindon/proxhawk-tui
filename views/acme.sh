# shellcheck shell=bash
# views/acme.sh - Datacenter > ACME (accounts, challenge plugins) and
# Node > Certificates (certificates, custom upload, ACME domains, order/renew).

# ---------------------------------------------------------------------------
# Datacenter > ACME. Row keys "account|name", "plugin|id".
# ---------------------------------------------------------------------------
v_dc_acme() {
    local row n=0
    local -a names f
    c_section "Accounts"
    table_spec "name:Account Name:20|contact:E-Mail:*|directory:Directory:**|status:Status:10"
    api_get rows /cluster/acme/account "" "name" || { c_api_error; return; }
    names=("${API_ROWS[@]}")
    table_header
    for row in "${names[@]}"; do
        if api_get rows "/cluster/acme/account/$row" "" "account.contact,directory,account.status"; then
            tsv_split f "${API_ROWS[0]}"
        else f=("" "" "")
        fi
        table_row "$row"$'\t'"${f[0]//mailto:/}"$'\t'"${f[1]}"$'\t'"${f[2]}"
        c_sel "$REPLY" "account|$row"; (( n++ ))
    done
    (( n )) || c_msg dim "No items"
    c_blank
    c_section "Challenge Plugins"
    TABLE_KEY_PREFIX="plugin|"
    view_table /cluster/acme/plugins "" "plugin:Plugin:20|type:Type:12|api:API:16|validation-delay:Validation Delay:17:s:r|nodes:Nodes:*"
}
VIEW_HINT[v_dc_acme]="a:Add e:Edit d:Remove Enter:View"
v_dc_acme__key() {
    local k=$1 key=$2 kind=${2%%|*} id=${2#*|}
    case $k in
        a|INS)
            local -a items=()
            T "Account"; items+=(account "$REPLY")
            T "Challenge Plugin"; items+=(plugin "$REPLY")
            if [[ -n ${CRUD_ANSWER[sub]-} ]]; then REPLY=${CRUD_ANSWER[sub]}
            else T "Add"; dlg_menu "$REPLY" "ACME" "${items[@]}" || return 0
            fi
            if [[ $REPLY == account ]]; then acme_account_add; else acme_plugin_form ""; fi ;;
        e)
            [[ -n $key ]] || return 0
            if [[ $kind == account ]]; then
                form_reset; FORM_ONLY="contact"; FORM_GET=""
                api_get rows "/cluster/acme/account/$id" "" "account.contact"
                FORM_VAL[contact]=${API_ROWS[0]//mailto:/}
                form_run "Edit: Account $id" PUT "/cluster/acme/account/$id" && content_load 1
            else
                acme_plugin_form "$id"
            fi ;;
        d|DEL)
            [[ -n $key ]] || return 0
            if [[ $kind == account ]]; then
                Tf "Deactivate and remove ACME account '%s'?" "$id"; confirm "$REPLY" || return 0
                api_exec "ACME Account $id - Deactivate" delete "/cluster/acme/account/$id"
            else
                Tf "Remove ACME plugin '%s'?" "$id"; confirm "$REPLY" || return 0
                api_exec_sync "Remove ACME plugin $id" delete "/cluster/acme/plugins/$id"; content_load 1
            fi ;;
        *) return 1 ;;
    esac
    return 0
}
v_dc_acme__enter() {
    local kind=${1%%|*} id=${1#*|}
    [[ -n $1 ]] || return
    if [[ $kind == account ]]; then api_get kv "/cluster/acme/account/$id"
    else api_get kv "/cluster/acme/plugins/$id"
    fi
    printf '%s\n' "${API_ROWS[@]}" | grep -v -e '^data' -e '^account.key' | tr '\t\036' '=,' > "$RUN_DIR/acme.txt"
    dlg_textbox "ACME $kind $id" "$RUN_DIR/acme.txt"
}

# Register an account: directory, terms of service, then name and e-mail.
acme_account_add() {
    local dir tos
    if [[ -n ${CRUD_ANSWER[directory]-} ]]; then dir=${CRUD_ANSWER[directory]}
    else
        local row; local -a items=()
        api_get rows /cluster/acme/directories "" "url,name" || { dlg_msg "ACME" "$API_ERR"; return; }
        for row in "${API_ROWS[@]}"; do items+=("${row%%$'\t'*}" "${row#*$'\t'}"); done
        dlg_menu "Register Account" "ACME Directory:" "${items[@]}" || return
        dir=$REPLY
    fi
    urlenc "$dir"
    api_get rows /cluster/acme/tos "directory=$REPLY" "" && tos=${API_ROWS[0]-}
    if [[ -n $tos && -z ${CRUD_ANSWER[directory]-} ]]; then
        Tf "Accept the Terms of Service of the CA?\n\n%s" "$tos"
        dlg_yesno "Register Account" "$REPLY" || return
    fi
    form_reset
    FORM_FIX[directory]=$dir
    [[ -n $tos ]] && FORM_FIX[tos_url]=$tos
    FORM_FIRST="name contact eab-kid eab-hmac-key"
    form_run "Register Account" POST /cluster/acme/account && content_load 1
}

# Add / edit a challenge plugin. DNS plugin credentials are edited as
# KEY=value lines (base64 "data" in the API), with the fields of the API.
acme_plugin_form() {
    local id=$1 type api data="" f="$RUN_DIR/acme-data.txt" ed=${CFG[editor]:-${VISUAL:-${EDITOR:-}}}
    [[ -z $ed ]] && { command -v nano >/dev/null && ed=nano || ed=vi; }
    if [[ -n $id ]]; then
        api_kv "/cluster/acme/plugins/$id" || { dlg_msg "ACME" "$API_ERR"; return; }
        type=${API_KV[type]-} api=${API_KV[api]-} data=${API_KV[data]-}
    else
        type=${CRUD_ANSWER[type]-}
        [[ -z $type ]] && { dlg_menu "Add: Challenge Plugin" "Type:" dns "DNS" standalone "Standalone (HTTP)" || return; type=$REPLY; }
    fi
    form_reset
    FORM_HIDE="data api type"
    [[ $type == standalone ]] && FORM_HIDE+=" validation-delay"
    FORM_FIRST="id validation-delay nodes disable"
    if [[ -n $id ]]; then FORM_GET="/cluster/acme/plugins/$id"; else FORM_FIX[type]=$type; fi
    if [[ $type == dns ]]; then
        if [[ -z $id ]]; then
            api=${CRUD_ANSWER[api]-}
            if [[ -z $api ]]; then
                local row; local -a items=()
                api_get rows /cluster/acme/challenge-schema "" "id,name" || return
                for row in "${API_ROWS[@]}"; do items+=("${row%%$'\t'*}" "${row#*$'\t'}"); done
                dlg_menu "DNS API" "DNS provider:" "${items[@]}" || return
                api=$REPLY
            fi
            FORM_FIX[api]=$api
        fi
        # Credentials: KEY=value lines, prefilled with the fields of the provider.
        if [[ -n ${CRUD_ANSWER[data]-} ]]; then
            printf '%s\n' "${CRUD_ANSWER[data]}" > "$f"
        else
            printf '%s' "$data" | base64 -d 2>/dev/null > "$f"
            if [[ ! -s $f ]]; then
                {
                    echo "# DNS API credentials for '$api' (KEY=value, one per line)."
                    api_get json /cluster/acme/challenge-schema "" ""
                    printf '%s' "${API_ROWS[0]}" | perl -MJSON -e '
                        my $d = decode_json(join("", <STDIN>));
                        for my $p (@$d) { next if $p->{id} ne $ARGV[0];
                            my $f = $p->{schema}{fields} // {};
                            print "# $p->{schema}{description}\n" if $p->{schema}{description};
                            for (sort keys %$f) { print "# $_: $f->{$_}{description}\n$_=\n" } }' "$api"
                } > "$f"
            fi
            # shellcheck disable=SC2086
            term_run $ed "$f"
        fi
        FORM_FIX[data]=$(grep -v -e '^#' -e '^[[:space:]]*$' "$f" | base64 -w 0)
    fi
    if [[ -n $id ]]; then form_run "Edit: Plugin $id" PUT "/cluster/acme/plugins/$id" && content_load 1
    else form_run "Add: Challenge Plugin ($type)" POST /cluster/acme/plugins && content_load 1
    fi
}

# ---------------------------------------------------------------------------
# Node > Certificates. Row keys: "cert|file", "domain|acmedomainN", "acct|".
# ---------------------------------------------------------------------------
v_node_certificates() {
    local k n=0
    c_section "Certificates"
    TABLE_KEY_PREFIX="cert|"
    view_table "/nodes/$CTX_NODE/certificates/info" "" "filename:File:20|issuer:Issuer:*|subject:Subject:*|public-key-type:Key Type:9|notafter:Expires:19:t|san:Subject Alternative Names:*"
    c_blank
    c_section "ACME"
    api_kv "/nodes/$CTX_NODE/config"
    local acct="default"
    if [[ -n ${API_KV[acme]-} ]]; then prop_get "${API_KV[acme]}" account && acct=$REPLY; fi
    c_kv_sel "Using Account" "$acct" "acct|"
    table_spec "domain:Domain:30|type:Type:10|plugin:Plugin:*"
    table_header
    for k in $(printf '%s\n' "${!API_KV[@]}" | grep '^acmedomain[0-9]' | sort -V); do
        local v=${API_KV[$k]} d plugin=standalone type=standalone
        d=${v%%,*}; d=${d#domain=}
        prop_get "$v" plugin && { plugin=$REPLY; type=dns; }
        [[ $plugin == standalone ]] && type=standalone
        table_row "$d"$'\t'"$type"$'\t'"$plugin"
        c_sel "$REPLY" "domain|$k"; (( n++ ))
    done
    # Legacy "acme: domains=a;b" entries.
    if prop_get "${API_KV[acme]-}" domains; then
        local d; for d in ${REPLY//;/ }; do table_row "$d"$'\t'"standalone"$'\t'"standalone"; c_add "$REPLY"; (( n++ )); done
    fi
    (( n )) || c_msg dim "No ACME domains configured."
}
VIEW_HINT[v_node_certificates]="u:Upload_Custom D:Delete_Custom a:Add_Domain e:Edit d:Remove A:Account O:Order_Now R:Renew V:Revoke Enter:View"
v_node_certificates__key() {
    local k=$1 key=$2 kind=${2%%|*} id=${2#*|} n=$CTX_NODE
    case $k in
        u) cert_upload ;;
        D)
            T "Delete the custom certificate and switch back to the self-signed one? pveproxy will be restarted."
            confirm "$REPLY" || return 0
            api_exec_sync "Delete custom certificate" delete "/nodes/$n/certificates/custom" --restart 1; content_load 1 ;;
        a|INS)
            local i=0
            api_kv "/nodes/$n/config"
            while [[ -n ${API_KV[acmedomain$i]-} ]]; do (( i++ )); done
            _cert_domain_form "acmedomain$i" "Add: Domain" ;;
        e) [[ $kind == domain ]] && _cert_domain_form "$id" "Edit: Domain"; [[ $kind == acct ]] && _cert_account_form ;;
        A) _cert_account_form ;;
        d|DEL)
            [[ $kind == domain ]] || return 0
            Tf "Remove ACME domain entry '%s'?" "$id"; confirm "$REPLY" || return 0
            api_exec_sync "Remove ACME domain" set "/nodes/$n/config" --delete "$id"; content_load 1 ;;
        O)
            T "Order a certificate for the configured domains now? pveproxy will be restarted with the new certificate."
            confirm "$REPLY" || return 0
            api_exec "Order ACME certificate" create "/nodes/$n/certificates/acme/certificate" --force 1 ;;
        R) api_exec "Renew ACME certificate" set "/nodes/$n/certificates/acme/certificate" --force 1 ;;
        V)
            T "Revoke the ACME certificate of this node? It cannot be undone."
            dlg_yesno "Revoke" "$REPLY" || return 0
            api_exec "Revoke ACME certificate" delete "/nodes/$n/certificates/acme/certificate" ;;
        *) return 1 ;;
    esac
    return 0
}
v_node_certificates__enter() {
    local kind=${1%%|*} id=${1#*|}
    case $kind in
        cert)
            if [[ $CTX_NODE == "$LOCAL_NODE" && -r /etc/pve/local/$id ]]; then
                openssl x509 -in "/etc/pve/local/$id" -noout -text > "$RUN_DIR/cert.txt" 2>&1
            else
                api_get kv "/nodes/$CTX_NODE/certificates/info"; printf '%s\n' "${API_ROWS[@]}" > "$RUN_DIR/cert.txt"
            fi
            pager_show "$RUN_DIR/cert.txt" "$id" ;;
        domain) _cert_domain_form "$id" "Edit: Domain" ;;
        acct) _cert_account_form ;;
    esac
}
_cert_domain_form() {
    form_reset
    FORM_GET="/nodes/$CTX_NODE/config" FORM_ONLY=$1
    form_run "$2" PUT "/nodes/$CTX_NODE/config" && content_load 1
}
_cert_account_form() {
    form_reset
    FORM_GET="/nodes/$CTX_NODE/config" FORM_ONLY="acme"
    form_run "Edit: ACME Account" PUT "/nodes/$CTX_NODE/config" && content_load 1
}
# Upload a custom certificate from PEM files on this host.
cert_upload() {
    local cf kf
    dlg_input "Upload Custom Certificate" "Certificate chain file (PEM):" "" || return 0; cf=$REPLY
    dlg_input "Upload Custom Certificate" "Private key file (PEM, empty = keep the current key):" "" || return 0; kf=$REPLY
    [[ -r $cf ]] || { dlg_msg "Upload" "Cannot read $cf"; return 0; }
    local -a args=(--certificates "$(< "$cf")" --force 1 --restart 1)
    [[ -n $kf ]] && { [[ -r $kf ]] || { dlg_msg "Upload" "Cannot read $kf"; return 0; }; args+=(--key "$(< "$kf")"); }
    api_exec_sync "Upload custom certificate" create "/nodes/$CTX_NODE/certificates/custom" "${args[@]}"
    content_load 1
}
