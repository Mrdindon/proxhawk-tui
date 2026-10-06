# shellcheck shell=bash
# ACME accounts/plugins (Datacenter) and node certificates, including a real
# certificate order with the configured DNS plugin.
# ACME_CONTACT: contact address of the staging test account (a real mailbox
# domain: Let's Encrypt refuses example.* addresses). Unset: account steps skipped.

test_acme() {
    local k contact=${ACME_CONTACT-}
    local staging=https://acme-staging-v02.api.letsencrypt.org/directory
    ctx root
    check "ACME: view" view acme

    # Plugins.
    reset_step; crud_answers sub=plugin type=standalone; preset id=pvt-standalone
    check "ACME: add standalone plugin" key a ""
    check "ACME: standalone created" api_has /cluster/acme/plugins plugin pvt-standalone
    view acme; reset_step; preset nodes="$NODE"
    check "ACME: edit standalone plugin" key e "plugin|pvt-standalone"
    check "ACME: standalone plugin edited" kv_is /cluster/acme/plugins/pvt-standalone nodes "$NODE"
    reset_step; crud_answers sub=plugin type=dns api=cf data=$'CF_Token=dummy\nCF_Account_ID=dummy'; preset id=pvt-dns validation-delay=20
    check "ACME: add DNS plugin (Cloudflare)" key a ""
    check "ACME: DNS plugin data stored" kv_like /cluster/acme/plugins/pvt-dns data "?*"
    view acme; reset_step; crud_answers data=$'CF_Token=dummy2'; preset validation-delay=40
    check "ACME: edit DNS plugin" key e "plugin|pvt-dns"
    check "ACME: DNS plugin edited" kv_is /cluster/acme/plugins/pvt-dns validation-delay 40
    for k in pvt-standalone pvt-dns; do reset_step; check "ACME: remove plugin $k" key d "plugin|$k"; done

    # Account on the Let's Encrypt staging directory.
    if [[ -z $contact ]]; then skip "ACME: staging account" "ACME_CONTACT not set"; else
        reset_step; crud_answers sub=account directory=$staging; preset name=pvetty-test contact="$contact"
        check "ACME: register staging account" key a ""
        check "ACME: account listed" api_has /cluster/acme/account name pvetty-test
        view acme
        check "ACME: account details" enter "account|pvetty-test"
        reset_step; preset contact="$contact"
        check "ACME: edit account" key e "account|pvetty-test"
        reset_step; check "ACME: deactivate account" key d "account|pvetty-test"
        check "ACME: account removed" api_lacks /cluster/acme/account name pvetty-test
    fi

    # Node certificates.
    ctx "node/$NODE"
    check "Certificates: view" view certificates
    reset_step; preset acmedomain1="pvetty-test.example.invalid,plugin=standalone"
    check "Certificates: add ACME domain" key a ""
    check "Certificates: domain saved" kv_like "/nodes/$NODE/config" acmedomain1 "pvetty-test.example.invalid*"
    view certificates; reset_step; preset acmedomain1="pvetty-test2.example.invalid,plugin=standalone"
    check "Certificates: edit domain" key e "domain|acmedomain1"
    reset_step; check "Certificates: remove domain" key d "domain|acmedomain1"
    api_kv "/nodes/$NODE/config"; local acme=${API_KV[acme]-}
    reset_step; preset acme="${acme:-account=default}"
    check "Certificates: edit ACME account" key A ""
    check "Certificates: view certificate" enter "cert|pve-ssl.pem"

    # Custom certificate: upload a self-signed one, then delete it.
    local d=$RUN_DIR/cert
    mkdir -p "$d"
    cp /etc/pve/local/pveproxy-ssl.pem "$d/orig.pem" 2>/dev/null; cp /etc/pve/local/pveproxy-ssl.key "$d/orig.key" 2>/dev/null
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$d/key.pem" -out "$d/cert.pem" -days 2 -subj "/CN=pvetty-test" >/dev/null 2>&1
    reset_step; answers "$d/cert.pem" "$d/key.pem"
    check "Certificates: upload custom certificate" key u ""
    check "Certificates: custom certificate active" bash -c "pvesh get /nodes/$NODE/certificates/info --output-format json | grep -q 'CN=pvetty-test'"
    reset_step
    check "Certificates: delete custom certificate" key D ""
    check "Certificates: custom certificate removed" bash -c "! pvesh get /nodes/$NODE/certificates/info --output-format json | grep -q pvetty-test"

    # Real order with the configured domains / plugin (restores a trusted certificate).
    api_kv "/nodes/$NODE/config"
    # ACME_NO_ORDER=1 skips it (Let's Encrypt limits duplicate certificates to 5 per week).
    if [[ ${ACME_NO_ORDER:-0} == 1 ]]; then
        skip "Certificates: order / renew" "ACME_NO_ORDER=1"
        if [[ -s $d/orig.pem ]]; then
            reset_step; answers "$d/orig.pem" "$d/orig.key"
            check "Certificates: previous certificate restored" key u ""
        fi
    elif [[ -n ${API_KV[acmedomain0]-} ]]; then
        reset_step
        check "Certificates: order certificate (ACME)" key O ""
        check "Certificates: Let's Encrypt certificate installed" bash -c "pvesh get /nodes/$NODE/certificates/info --output-format json | grep -q \"Let's Encrypt\""
        reset_step
        check "Certificates: renew certificate (ACME)" key R ""
    else
        skip "Certificates: order" "no ACME domain configured on $NODE"
    fi
}
