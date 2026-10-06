# pvetty — Extending

Everything visible is built from small, independent pieces. This page shows
how to add each of them. After a change, run `tools/selftest.sh` (read) and the matching section of
`tools/integration-test.sh` (write, see TESTING.md).

## Object types and contexts

The selected tree entry defines the *context* (`lib/views.sh`, `ctx_set`):

| Tree id | `CTX_TYPE` | Context variables |
|---------|-----------|-------------------|
| `root` | `dc` | — |
| `node/<node>` | `node` | `CTX_NODE` |
| `qemu/<vmid>`, `lxc/<vmid>` | `qemu`, `lxc` | `CTX_NODE`, `CTX_VMID`, `CTX_NAME` |
| `storage/<node>/<id>` | `storage` | `CTX_NODE`, `CTX_STORAGE` |
| `pool/<id>` | `pool` | `CTX_POOL` |
| `network/<node>/zone/<id>` | `sdn` | `CTX_NODE`, `CTX_NET` |
| `folder/<type>` | `folder` | — |

Resource data of the whole cluster is always available in the `R_*` arrays
(`R_TYPE`, `R_STATUS`, `R_NODE`, `R_NAME`, `R_CPU`, `R_MEM`, ...) indexed by
id, and `RES_IDS` lists every id.

## Adding a panel (menu entry)

1. Add the entry to the menu of the type (`views/<type>.sh`):

   ```bash
   view_menu node \
       ...
       "pci|PCI Devices|m_hardware|1" \      # id | Label | icon key | indent level
       ...
   ```

2. Write the handler `v_<type>_<id>`. Most panels are one line thanks to the
   generic table and key/value builders:

   ```bash
   v_node_pci() {
       view_table "/nodes/$CTX_NODE/hardware/pci" "" \
           "id:ID:14|vendor_name:Vendor:*|device_name:Device:**|iommugroup:IOMMU Group:12:s:r"
   }
   ```

   Table specification: `field:Header:width[:format[:align]]` separated by `|`.

   - width: a number, `*` (one share of the remaining width) or `**` (two shares)
   - format: `s` string, `b` bytes, `t` date-time, `ts` short date-time, `d`
     date, `u` uptime, `pct` (value × 10000), `bool`, `nbool` (negated),
     `status` (coloured), `task` (task status)
   - align: `l` (default) or `r`
   - fields use the broker syntax (`a.b`, `x*100`, `x:i`, `x#`, `@path;...`)

   `view_table PATH QUERY SPEC [key column] [sort column] [sort options]`
   — the key column value is passed to the row callbacks.

   Other builders (`lib/content.sh`): `view_kv`, `c_section`, `c_kv`,
   `c_kv_sel`, `c_add`, `c_sel`, `c_text`, `c_msg`, `table_spec`,
   `table_header`, `table_row`, `table_add`; widgets (`lib/widgets.sh`):
   `usage_line`, `bar`, `chart`; graphs (`lib/rrd.sh`): `rrd_graphs`.

3. Optional callbacks and flags:

   ```bash
   v_node_pci__enter() {            # Enter / double-click on a row, $1 = row key
       dlg_msg "PCI device" "$1"
   }
   v_node_pci__key() {              # extra keys, rc 0 = handled
       case $1 in
           x) ...; return 0 ;;
       esac
       return 1
   }
   VIEW_HINT[v_node_pci]="Enter:Details x:Something"   # footer hints ("_" = space)
   VIEW_LIVE[v_node_pci]=1                             # reload on auto refresh
   ```

4. Add an icon for the new `m_*` key in `lib/glyphs.sh` (`_NERD` code point and
   `_UNICODE` character) — optional, a missing icon is simply not shown.

### Dynamic menus

Define `menu_<type>()` and call `menu_add id "Label" icon level` (see
`menu_storage` which builds the menu from the storage content types).

### Shared panels

When several types share a panel, write a generic function and small wrappers
(see the loop at the end of `views/guest.sh` that registers the same panels
for `qemu` and `lxc`).

## Adding a new object type

1. Make `ctx_set` (`lib/views.sh`) recognise its tree id.
2. Make `tree_build` (`lib/resources.sh`) insert it, and `res_label` /
   `res_icon` render it.
3. Create `views/<type>.sh` with `view_menu <type> ...`, `title_<type>()`,
   optional `toolbar_<type>()` and the `v_<type>_*` handlers.

## Add / Edit / Remove (CRUD) and forms

Most configuration panels need no code besides the table and one `crud`
declaration (lib/crud.sh). Example (Datacenter > Groups):

```bash
v_dc_groups() { view_table /access/groups "" "groupid:Group name:24|comment:Comment:*|users:Users:*"; }
crud v_dc_groups label="Group" add=/access/groups edit="/access/groups/{1}" del="/access/groups/{1}" first="groupid comment"
```

The keys `a`, `e`/`Enter`, `d`, the button line and the footer hints are
automatic. The dialogs are generated from the API definition of the calls.

Attributes:

| Attribute | Meaning |
|-----------|---------|
| `add=` `edit=` `del=` `get=` | API paths (POST, PUT, DELETE, GET for prefill) |
| `{1}` `{2}`... `{key}` | parts of the selected row key (`a|b`) |
| `{node}` `{vmid}` `{gtype}` `{storage}` `{pool}` `{net}` | context |
| `{s1}` `{s2}` | selected row key, for "add a child of the selected row" |
| `{?name:Prompt[:choice_fn]}` | asked before the dialog (input box or list) |
| `label=` | object name used in titles |
| `first=` `hide=` `only=` `editonly=` | field order / visibility |
| `fix="k=v ..."` `editfix=` | fixed parameters (placeholders allowed) |
| `plugin=` `types=` `typefield=` `pathtype=1` `typefields=` | typed objects (see lib/crud.sh) |
| `choices="field:choice_fn ..."` | lists offered for free text fields |
| `delargs="--k v"` | extra arguments of the removal |
| `async=1` `sync=1` `result=1` | background call / wait / display the output |
| `noadd=1` `noedit=1` `nodel=1` | disable an operation |
| `extra="K:Label ..."` | extra keys handled by `v_xxx__key`, shown as buttons |

Several kinds of objects in one panel:

```bash
v_dc_mapping() {
    c_section "PCI Devices"; TABLE_KEY_PREFIX="pci|"; view_table /cluster/mapping/pci "" "id:ID:20|map:Mapping:*"
    c_section "USB Devices"; TABLE_KEY_PREFIX="usb|"; view_table /cluster/mapping/usb "" "id:ID:20|map:Mapping:*"
}
crud v_dc_mapping:pci label="PCI Mapping" add=/cluster/mapping/pci edit="/cluster/mapping/pci/{1}" del="/cluster/mapping/pci/{1}"
crud v_dc_mapping:usb label="USB Mapping" add=/cluster/mapping/usb edit="/cluster/mapping/usb/{1}" del="/cluster/mapping/usb/{1}"
```

Forms can also be opened directly:

```bash
form_reset
FORM_GET="/nodes/$CTX_NODE/dns" FORM_ONLY="search dns1 dns2 dns3"
form_run "Edit: DNS" PUT "/nodes/$CTX_NODE/dns" && content_load 1
```

See the header of lib/form.sh for every `FORM_*` option (labels, choices,
fixed values, plugin types, presets used by the tests...).

## Toolbar buttons and actions

Toolbars are built per type by `toolbar_<type>()` (`lib/actions.sh`):

```bash
toolbar_node() {
    #      hot key  label        icon                 enabled  action function
    tb_add b       "Reboot"     "${G[btn_reboot]}"   1        act_node_reboot
    tb_add W       "Wake-on-LAN" "${G[btn_start]}"   1        act_node_wol
}

act_node_wol() {
    confirm "Send a Wake-on-LAN packet to $CTX_NODE?" || return
    api_exec "Wake-on-LAN $CTX_NODE" create "/nodes/$CTX_NODE/wakeonlan"
}
```

- `api_exec DESC METHOD PATH [--opt value ...]` runs `pvesh` in the
  background (METHOD = `create`, `set`, `delete`); completion is reported in
  the footer and the data are refreshed.
- `api_exec_sync` does the same synchronously with a spinner.
- Dialogs: `dlg_yesno`, `dlg_input`, `dlg_password`, `dlg_menu`, `dlg_msg`,
  `dlg_textbox`; results in `REPLY`.
- `term_run CMD...` runs an interactive program outside the TUI,
  `node_cmd NODE CMD...` does it on a node (SSH for remote nodes).

The hot key is underlined in the label when the letter is present, otherwise
it is shown in parentheses. Disabled buttons are dimmed and their key reports
"not available".

## Reading the API

```bash
api_get rows "/nodes/$CTX_NODE/qemu" "full=1" "vmid,name,status,maxmem:i"
for row in "${API_ROWS[@]}"; do
    tsv_split f "$row"            # keeps empty fields
    echo "${f[0]} ${f[1]}"
done

api_kv "/nodes/$CTX_NODE/dns"     # -> API_KV[search], API_KV[dns1]...
api_row "/nodes/$CTX_NODE/status" "" "cpu*10000,memory.used"   # -> API_F[0], API_F[1]
```

On error the functions return 1 and set `API_ERR` (`c_api_error` displays it).
Set `API_TTL=<seconds>` before calls to cache identical requests.

## Themes

Create `themes/<name>.sh`; only override what differs from `default.sh`:

```bash
# themes/solarized.sh
TH_BG="48;5;234"                # optional: painted background
TH[norm]="38;5;245"
TH[accent]="38;5;136"
TH[sel]="38;5;230;48;5;33"
TH[graph1]="38;5;37"
TH[graph2]="38;5;166"
```

Values are SGR parameters (`38;5;N` foreground, `48;5;N` background, `1`
bold, `4` underline). The tokens are listed in `themes/default.sh`. Select it
with `theme = solarized`.

## Icon sets

`lib/glyphs.sh` defines the `nerd` set as code points (`_NERD`), the
`unicode` set as characters (`_UNICODE`) and the `ascii` set inline. Keys must
exist in every set; use single-cell characters only.

## Languages

See [I18N.md](I18N.md).

## Plugins

A plugin adds panels or buttons without changing the sources. It is a bash
file `plugins/<name>.sh` (or `~/.config/pvetty/plugins/<name>.sh`), loaded
after the views when its name is listed in the `plugins` setting
(`F4` › Plugins, or `PVETTY_PLUGINS`). The first lines describe it:

```bash
# plugin: uptime-report
# description: Datacenter > Uptime Report, the guests sorted by uptime

menu_extend dc "uptime|Uptime Report|m_summary|0"   # id|label|icon|level

v_dc_uptime() {
    local id
    c_section "Guests by uptime"
    for id in "${RES_IDS[@]}"; do
        [[ ${R_TYPE[$id]} == qemu || ${R_TYPE[$id]} == lxc ]] || continue
        [[ ${R_STATUS[$id]} == running ]] || continue
        fmt_uptime "${R_UPTIME[$id]:-0}"
        c_kv "${R_VMID[$id]} ${R_NAME[$id]}" "$REPLY"
    done
}
VIEW_LIVE[v_dc_uptime]=1
```

- `menu_extend <type> "<id>|<label>|<icon>|<level>"` appends a menu entry to
  the objects of a type (`dc`, `node`, `qemu`, `lxc`, `storage`, `pool`...);
  the panel is the function `v_<type>_<id>`, written like the panels of
  `views/` (see [Adding a panel](#adding-a-panel-menu-entry)). Row and key
  callbacks (`v_<type>_<id>__enter`, `__key`), `VIEW_HINT` and `VIEW_LIVE`
  work the same way.
- `toolbar_extend <type> <function>`: the function is called when the toolbar
  is built and adds buttons with `tb_add`.
- Every helper of the views is available (`api_get`, `api_exec`, dialogs,
  `crud`, `guest_ip_cached`...).

`tools/selftest.sh` renders plugin panels when the plugin is enabled
(`PVETTY_PLUGINS=name tools/selftest.sh`). The bundled plugins
(`community-scripts`, `ansible-inventory`) are complete examples.

## Coding conventions

- bash ≥ 4.3, no external commands in rendering paths (no sub-shells in
  loops, results returned in `REPLY` or arrays).
- English identifiers, comments and source strings.
- Every user-visible string goes through `T` / `Tf`, or is a menu label / a
  table header (translated automatically).
- Keep functions small and side effects explicit (globals in capitals).
