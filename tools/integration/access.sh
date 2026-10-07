# shellcheck shell=bash
# Datacenter > Permissions: users, tokens, TFA, groups, pools, roles, realms, ACL.

test_access() {
    local u="proxhawk-tui-test@pve" g="proxhawk-tui-test-grp" p="proxhawk-tui-test-pool" r="TuiTestRole" k
    ctx root

    # Groups (needed by the user).
    check "Groups: view" view groups
    reset_step; preset groupid=$g comment="proxhawk-tui test group"
    check "Groups: add" key a ""
    check "Groups: created" kv_is "/access/groups/$g" comment "proxhawk-tui test group"
    view groups; reset_step; preset comment="edited"
    check "Groups: edit" key e "$g"
    check "Groups: edited" kv_is "/access/groups/$g" comment "edited"

    # Users.
    check "Users: view" view users
    reset_step; crud_answers realm=${u#*@} name=${u%@*}; preset password=Proxhawk-Test-123 comment="proxhawk-tui test user" email=test@example.invalid groups=$g firstname=Test
    check "Users: add" key a ""
    check "Users: created" kv_is "/access/users/$u" firstname Test
    view users; reset_step; preset comment="edited user" enable=0
    check "Users: edit" key e "$u"
    check "Users: edited" kv_is "/access/users/$u" enable 0
    reset_step; preset password=Proxhawk-Test-456 confirmation-password=""
    check "Users: change password" key p "$u"

    # PAM users: the Linux account is created only when the user proxhawk-tui runs
    # as may create Linux accounts (root, or useradd allowed by sudo) and may
    # add users to the pam realm.
    test_pam_users

    # API tokens.
    check "API Tokens: view" view tokens
    reset_step; crud_answers userid=$u tokenid=t1; preset comment="test token" privsep=1
    check "API Tokens: add" key a ""
    check "API Tokens: secret returned" grep -q value <<< "$FORM_RESULT"
    check "API Tokens: created" kv_is "/access/users/$u/token/t1" comment "test token"
    view tokens; reset_step; preset comment="edited token"
    check "API Tokens: edit" key e "$u|t1"
    check "API Tokens: edited" kv_is "/access/users/$u/token/t1" comment "edited token"
    reset_step
    check "API Tokens: remove" key d "$u|t1"
    check "API Tokens: removed" api_lacks "/access/users/$u/token" tokenid t1

    # Two factor: recovery keys, then a TOTP entry with a code computed here.
    check "Two Factor: view" view tfa
    reset_step; crud_answers userid=$u; preset type=recovery description="proxhawk-tui recovery"
    check "Two Factor: add recovery keys" key a ""
    check "Two Factor: keys returned" grep -q -i recovery <<< "$FORM_RESULT"
    local secret=JBSWY3DPEHPK3PXP code
    code=$(python3 -c 'import hmac,hashlib,struct,time,base64,sys
k=base64.b32decode(sys.argv[1]); c=struct.pack(">Q",int(time.time())//30)
h=hmac.new(k,c,hashlib.sha1).digest(); o=h[-1]&15
print("%06d"%((struct.unpack(">I",h[o:o+4])[0]&0x7fffffff)%1000000))' "$secret")
    reset_step; crud_answers userid=$u
    preset type=totp description="proxhawk-tui totp" totp="otpauth://totp/proxhawk-tui:test?secret=$secret&issuer=proxhawk-tui&algorithm=SHA1&digits=6&period=30" value="$code"
    check "Two Factor: add TOTP" key a ""
    view tfa
    local kt="" kr="" kk
    for kk in "${C_SELK[@]}"; do
        [[ $kk == "$u|"* ]] || continue
        api_kv "/access/tfa/${kk%%|*}/${kk#*|}"
        [[ ${API_KV[type]-} == totp ]] && kt=$kk
        [[ ${API_KV[type]-} == recovery ]] && kr=$kk
    done
    if [[ -n $kt ]]; then
        reset_step; preset description="edited totp" enable=1
        check "Two Factor: edit TOTP" key e "$kt"
        check "Two Factor: edited" kv_is "/access/tfa/$u/${kt#*|}" description "edited totp"
    else ko "Two Factor: TOTP listed" "no row"; fi
    view users; reset_step
    check "Users: unlock TFA" key u "$u"
    view tfa
    for kk in "$kt" "$kr"; do
        [[ -n $kk ]] || continue
        reset_step
        check "Two Factor: remove ${kk#*|}" key d "$kk"
    done
    check "Two Factor: all removed" api_lacks /access/tfa userid "$u"

    # Roles.
    check "Roles: view" view roles
    reset_step; preset roleid=$r privs="VM.Audit,Datastore.Audit"
    check "Roles: add" key a ""
    check "Roles: created" api_has /access/roles roleid "$r"
    view roles; reset_step; preset privs="VM.Audit,VM.PowerMgmt"
    check "Roles: edit" key e "$r"
    check "Roles: edited" kv_is "/access/roles/$r" "VM.PowerMgmt" "1"

    # Pools.
    check "Pools: view" view pools
    reset_step; preset poolid=$p comment="proxhawk-tui test pool"
    check "Pools: add" key a ""
    check "Pools: created" api_has /pools poolid "$p"
    view pools; reset_step; preset comment="edited pool"
    check "Pools: edit" key e "$p"
    check "Pools: edited" api_has /pools comment "edited pool" "poolid=$p"

    # Permissions (ACL).
    check "Permissions: view" view permissions
    reset_step; crud_answers acltype=users; preset path="/pool/$p" users=$u roles=$r propagate=1
    check "Permissions: add user permission" key a ""
    check "Permissions: created" api_has /access/acl ugid "$u"
    reset_step; crud_answers acltype=groups; preset path=/ groups=$g roles=PVEAuditor
    check "Permissions: add group permission" key a ""
    view permissions
    rowkey "/pool/$p|user|$u|$r"; k=$REPLY
    check "Permissions: remove user permission" key d "$k"
    check "Permissions: user removed" api_lacks /access/acl ugid "$u"
    rowkey "/|group|$g|PVEAuditor"; k=$REPLY
    check "Permissions: remove group permission" key d "$k"

    # Realms: LDAP realm (the sync is expected to fail: no LDAP server).
    check "Realms: view" view realms
    reset_step; crud_answers type=ldap; preset realm=pvtldap server1=127.0.0.1 base_dn="dc=example,dc=invalid" user_attr=uid comment="proxhawk-tui test realm"
    check "Realms: add LDAP" key a ""
    check "Realms: created" kv_is /access/domains/pvtldap comment "proxhawk-tui test realm"
    view realms; reset_step; preset comment="edited realm" port=1389
    check "Realms: edit" key e pvtldap
    check "Realms: edited" kv_is /access/domains/pvtldap port 1389
    reset_step; preset dry-run=1 scope=users
    if key s pvtldap; then ko "Realms: sync (no server)" "unexpected success"
    else ok "Realms: sync reports the LDAP error ($STATUS_MSG)"; fi
    reset_step; crud_answers type=openid; preset realm=pvtoidc issuer-url=https://login.example.invalid client-id=proxhawk-tui
    check "Realms: add OpenID" key a ""
    view realms; reset_step
    check "Realms: remove OpenID" key d pvtoidc
    view realms; reset_step
    check "Realms: remove LDAP" key d pvtldap
    check "Realms: removed" api_lacks /access/domains realm pvtldap

    # Cleanup in dependency order.
    view pools; reset_step
    check "Pools: remove" key d "$p"
    check "Pools: removed" api_lacks /pools poolid "$p"
    view roles; reset_step
    check "Roles: remove" key d "$r"
    view users; reset_step
    check "Users: remove" key d "$u"
    check "Users: removed" api_lacks /access/users userid "$u"
    view groups; reset_step
    check "Groups: remove" key d "$g"
    check "Groups: removed" api_lacks /access/groups groupid "$g"
}

# Run the API helper as another user (like the start-up choice).
as_user() {
    api_stop
    user_apply "$1"
    api_start
}
pam_add() {     # pam_add <name>: Add user in the pam realm, account creation accepted
    reset_step; crud_answers realm=pam name="$1" create_account=1; preset password=Proxhawk-Pam-123 comment="proxhawk-tui test"
    view users; key a ""
}
pam_cleanup() {
    local n
    for n in proxhawk-tui-t-new proxhawk-tui-t-adm proxhawk-tui-t-nos; do
        pveum user delete "$n@pam" >/dev/null 2>&1; id "$n" >/dev/null 2>&1 && userdel -r "$n" >/dev/null 2>&1
    done
    pveum user delete proxhawk-tui-t-pve@pve >/dev/null 2>&1
    rm -f /etc/sudoers.d/proxhawk-tui-test
}
test_pam_users() {
    local new=proxhawk-tui-t-new
    pam_cleanup
    # As root@pam.
    pam_add "$new"
    check "PAM user (root@pam): Linux account created" id "$new"
    check "PAM user (root@pam): Proxmox VE user created" api_has /access/users userid "$new@pam"
    check "PAM user (root@pam): Linux password set" bash -c "grep -q '^$new:\\\$' /etc/shadow"
    pveum user delete "$new@pam" >/dev/null 2>&1; userdel -r "$new" >/dev/null 2>&1
    # Test users: Administrator in Proxmox VE, different Linux rights.
    useradd -m proxhawk-tui-t-adm && useradd -m proxhawk-tui-t-nos
    printf 'proxhawk-tui-t-adm ALL=(root) NOPASSWD: %s\n' "$(command -v useradd)" > "$RUN_DIR/sudoers"
    check "PAM user: sudo rule for useradd (visudo -c)" visudo -cf "$RUN_DIR/sudoers"
    install -m 440 "$RUN_DIR/sudoers" /etc/sudoers.d/proxhawk-tui-test
    pveum user add proxhawk-tui-t-adm@pam && pveum user add proxhawk-tui-t-nos@pam && pveum user add proxhawk-tui-t-pve@pve
    pveum acl modify / --users proxhawk-tui-t-adm@pam,proxhawk-tui-t-nos@pam,proxhawk-tui-t-pve@pve --roles Administrator
    # pve realm user: no Linux account, refused.
    as_user proxhawk-tui-t-pve@pve; pam_add "$new"
    check "PAM user (pve realm user): refused" eval '[[ $LAST_MSG == *"may not create Linux accounts"* ]] && ! id $new'
    # PAM user without sudo rights: refused.
    as_user proxhawk-tui-t-nos@pam; pam_add "$new"
    check "PAM user (no sudo): refused" eval '[[ $LAST_MSG == *"may not create Linux accounts"* ]] && ! id $new'
    # PAM user allowed to run useradd with sudo: created through sudo.
    as_user proxhawk-tui-t-adm@pam; pam_add "$new"
    check "PAM user (sudo useradd): Linux account created" id "$new"
    check "PAM user (sudo useradd): Proxmox VE user created" api_has /access/users userid "$new@pam"
    pveum user delete "$new@pam" >/dev/null 2>&1; userdel -r "$new" >/dev/null 2>&1
    # Same, without the Proxmox VE right to add pam users: refused.
    pveum acl delete / --users proxhawk-tui-t-adm@pam --roles Administrator
    pveum acl modify / --users proxhawk-tui-t-adm@pam --roles PVEAuditor
    as_user proxhawk-tui-t-adm@pam; pam_add "$new"
    check "PAM user (sudo, no Realm.AllocateUser): refused" eval '[[ $STATUS_MSG == *Realm.AllocateUser* ]] && ! id $new'
    as_user root@pam
    pam_cleanup
    check "PAM user: test accounts removed" eval '! id proxhawk-tui-t-adm && ! id proxhawk-tui-t-nos && [[ ! -e /etc/sudoers.d/proxhawk-tui-test ]]'
}
