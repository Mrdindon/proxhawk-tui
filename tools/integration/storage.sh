# shellcheck shell=bash
# Storage panels: summary, content (upload, download, templates, remove),
# permissions. Uses the "pvetty-test-dir" storage of the cluster section.

test_storage() {
    local s=pvetty-test-dir k
    if ! pvesh get "/storage/$s" >/dev/null 2>&1; then
        mkdir -p /var/tmp/pvetty-test-dir
        pvesh create /storage --storage $s --type dir --path /var/tmp/pvetty-test-dir --content iso,vztmpl,backup,snippets,import >/dev/null
    else
        pvesh set "/storage/$s" --content iso,vztmpl,backup,snippets,import >/dev/null
    fi
    wait_for 30 bash -c "pvesh get /cluster/resources --type storage --output-format json | grep -q 'storage/$NODE/$s'"
    ctx "storage/$NODE/$s"
    for k in summary iso vztmpl backup snippets import permissions; do check "Storage > $k: view" view "$k"; done

    # Upload a local ISO image.
    dd if=/dev/zero of=/var/tmp/pvetty-test.iso bs=1M count=2 status=none
    view iso
    reset_step; crud_answers file=/var/tmp/pvetty-test.iso
    check "ISO Images: upload" key U ""
    check "ISO Images: uploaded" api_has "/nodes/$NODE/storage/$s/content" volid "$s:iso/pvetty-test.iso" "content=iso"
    view iso; reset_step
    check "ISO Images: remove" key d "$s:iso/pvetty-test.iso"
    check "ISO Images: removed" api_lacks "/nodes/$NODE/storage/$s/content" volid "$s:iso/pvetty-test.iso" "content=iso"

    # Download from URL (small ISO).
    reset_step; answers "https://boot.netboot.xyz/ipxe/netboot.xyz.iso" "pvetty-netboot.iso"
    check "ISO Images: download from URL" key u ""
    check "ISO Images: downloaded" api_has "/nodes/$NODE/storage/$s/content" volid "$s:iso/pvetty-netboot.iso" "content=iso"
    view iso; reset_step
    check "ISO Images: remove download" key d "$s:iso/pvetty-netboot.iso"

    # Snippets upload.
    printf '#cloud-config\n' > /var/tmp/pvetty-test.yaml
    view snippets
    reset_step; crud_answers file=/var/tmp/pvetty-test.yaml
    check "Snippets: upload" key U ""
    check "Snippets: uploaded" test -f /var/tmp/pvetty-test-dir/snippets/pvetty-test.yaml
    view snippets; reset_step
    check "Snippets: remove" key d "$s:snippets/pvetty-test.yaml"

    # CT templates: appliance list, download, remove.
    view vztmpl
    reset_step
    local t
    t=$(pvesh get "/nodes/$NODE/aplinfo" --output-format json | grep -o '"template":"alpine[^"]*"' | head -1 | cut -d'"' -f4)
    if [[ -n $t ]]; then
        answers "$t"
        check "CT Templates: download $t" key T ""
        check "CT Templates: downloaded" api_has "/nodes/$NODE/storage/$s/content" volid "$s:vztmpl/$t" "content=vztmpl"
        view vztmpl; reset_step
        check "CT Templates: remove" key d "$s:vztmpl/$t"
    else skip "CT Templates: download" "appliance list empty (pveam update)"; fi

    # Permissions.
    view permissions
    reset_step; crud_answers acltype=users; preset users=root@pam roles=PVEDatastoreUser
    check "Storage Permissions: add" key a ""
    view permissions; rowkey "/storage/$s|*"
    reset_step; check "Storage Permissions: remove" key d "$REPLY"

    # Remove the test storage.
    ctx root; view storage
    reset_step; check "Storage: remove test storage" key d "$s"
    rm -rf /var/tmp/pvetty-test-dir /var/tmp/pvetty-test.iso /var/tmp/pvetty-test.yaml
}
