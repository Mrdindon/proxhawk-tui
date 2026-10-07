# proxhawk-tui — Configuration

Settings are read, in this order (later wins):

1. built-in defaults (`lib/core.sh`, array `CFG`)
2. `/etc/proxhawk-tui.conf`
3. `~/.config/proxhawk-tui/proxhawk-tui.conf` (or `$XDG_CONFIG_HOME/proxhawk-tui/proxhawk-tui.conf`)
4. files given with `-c FILE`
5. environment variables `PROXHAWK_TUI_<KEY>` (upper case, e.g. `PROXHAWK_TUI_THEME=dark`)
6. command line options

The user menu (`F4`) writes the changed keys into the user configuration file.

## Configuration file

Plain `key = value` lines, `#` starts a comment. Unknown keys are ignored.
See [`conf/proxhawk-tui.conf.example`](../conf/proxhawk-tui.conf.example).

| Key | Default | Values | Description |
|-----|---------|--------|-------------|
| `language` | `auto` | `auto`, `en`, `fr`, `de`, `es`, `zh_CN`, `ru`... (34 languages) | interface language; `auto` = the locale when it is not English, else the datacenter language, else English (see [I18N.md](I18N.md)) |
| `glyphs` | `auto` | `auto`, `nerd`, `unicode`, `ascii` | icon set; `auto` = `unicode` on UTF-8 terminals (`nerd` when `NERD_FONT=1` is exported), `ascii` otherwise |
| `theme` | `auto` | `auto`, `default`, `dark`, `light`, `basic`, any `themes/<name>.sh` | colour theme; `auto` = `default` with 256 colours, `basic` otherwise |
| `backend` | `auto` | `auto`, `broker`, `pvesh`, `replay` | API access for reads (see ARCHITECTURE.md); `replay` serves answers recorded with `PROXHAWK_TUI_RECORD` (tests) |
| `dialog` | `auto` | `auto`, `dialog`, `whiptail`, `builtin` | dialog tool |
| `refresh` | `5` | seconds, `0` = off | automatic refresh interval |
| `mouse` | `1` | `0`, `1` | mouse support |
| `tree_width` | `0` | columns, `0` = automatic (22 % of the width, 24–40) | width of the resource tree |
| `task_rows` | `5` | rows, `0` = hidden | height of the Tasks / Cluster log panel |
| `graph_timeframe` | `hour` | `hour`, `day`, `week`, `month`, `year` | initial RRD graph timeframe (`t` cycles) |
| `show_tags` | `1` | `0`, `1` | show guest tags in the tree |
| `confirm` | `1` | `0`, `1` | ask before power and destructive actions (removing a guest always asks for its ID) |
| `editor` | | command | editor for notes (default `$VISUAL`, `$EDITOR`, `nano`, `vi`) |
| `pager` | | command | pager for logs (default `$PAGER`, `less -R`) |
| `icons` | `1` | `0`, `1` | `0` removes the icons of the tree, menus and buttons (objects get a bullet) |
| `startup` | `root` | `root`, `last`, a tree id (`qemu/100`, `node/pve1`...) | initial selection; `last` restores the selection of the previous session |
| `confirm_quit` | `1` | `0`, `1` | ask before quitting while actions started by proxhawk-tui are running or queued |
| `ip_column` | `1` | `0`, `1` | IP column of the guests in the search grids (LXC interfaces, guest agent, neighbour table; cached 60 s) |
| `ssh_user` | `root` | user | default user of the SSH console of VMs |
| `ssh_key` | | file | private key of the SSH console (`ssh -i`) |
| `ssh_jump` | | `user@host:port` | jump host of the SSH console (`ssh -J`) |
| `ssh_options` | | options | extra ssh options, e.g. `-o StrictHostKeyChecking=no` |
| `console_host` | | host name | host of the browser console URLs (default: IP of the node) |
| `plugins` | | names | enabled plugins, space separated (see [Plugins](#plugins)) |
| `onboarding` | `1` | `0`, `1` | first run wizard (icons, theme, mouse) when no user configuration exists |
| `queue_parallel` | `2` | number | queued / batch actions running at the same time |
| `cli_output` | `json` | `json`, `table` | default output of the subcommands (see [CLI.md](CLI.md)) |
| `user` | | `name@realm` | Proxmox VE user to run as (see [Running as another user](#running-as-another-user)); empty = launching user |
| `ask_user` | `1` | `0`, `1` | ask at start-up which user to run as (`0`: always the launching user) |

### Key bindings

The global keys can be changed with `key.<action> = <keys>` (several keys
separated by spaces). The help window (`F1`) shows the current bindings.

| Action | Default | Action | Default |
|--------|---------|--------|---------|
| `help` | `F1 ?` | `docs` | `F7` |
| `search` | `/` | `refresh` | `r F5` |
| `auto_refresh` | `F6` | `view` | `v` |
| `tasklog` | `l` | `create_vm` | `F2 V` |
| `create_ct` | `F3 C` | `user_menu` | `F4 U` |
| `quit` | `q F10` | | |

Key names: letters and symbols as typed, `F1`..`F12`, `C-x` (Ctrl+x), `M-x`
(Alt+x), `ENTER`, `ESC`, `TAB`, `SPACE`, `DEL`, `INS`. Navigation keys,
toolbar and panel keys are not remapped.

```
key.help = F1 h
key.quit = C-q
```

### Colour overrides

`color.<token> = <value>` changes one colour of the current theme. Tokens are
the keys of the `C` array of the theme files (`norm`, `accent`, `sel`,
`border`, `title`, `ok`, `warn`, `err`, `dim`, `btn`, `btn_key`...). Values:

- `#rrggbb` (foreground) or `bg=#rrggbb`; truecolor when `COLORTERM` is
  `truecolor` / `24bit`, nearest 256-colour otherwise;
- ANSI names: `red`, `bright-blue`, `bg=black`..., attributes `bold`, `dim`,
  `italic`, `underline`, `reverse`, combined with spaces or `,`;
- raw SGR parameters (`38;5;208`), or `default`.

```
color.accent = #ff8800 bold
color.sel = bg=#264f78 white
```

## Command line

```
proxhawk-tui [options]
  -l, --lang CODE       interface language
  -g, --glyphs SET      nerd | unicode | ascii
  -t, --theme NAME      default | dark | light | basic | <custom>
  -b, --backend NAME    broker | pvesh | replay
  -r, --refresh SEC     auto refresh interval (0 = off)
  -c, --config FILE     additional configuration file
      --no-mouse        disable mouse support
  -u, --user USER       run as this Proxmox VE user (its permissions apply)
      --select ID       initial selection: root, node/<name>, qemu/<vmid>,
                        lxc/<vmid>, storage/<node>/<storage>, pool/<name>
  -h, --help            help
  -V, --version         version

proxhawk-tui <nodes|guests|tasks|storage|api> ...   non-interactive commands (CLI.md)
```

## Environment

| Variable | Effect |
|----------|--------|
| `PROXHAWK_TUI_<KEY>` | overrides a configuration key (`PROXHAWK_TUI_GLYPHS=nerd`) |
| `NERD_FONT=1` | `glyphs = auto` selects the Nerd Font set |
| `PROXHAWK_TUI_DEBUG=1` | debug log to `$PROXHAWK_TUI_LOG` (default `/tmp/proxhawk-tui-debug.log`) |
| `VISUAL`, `EDITOR`, `PAGER` | editor and pager |
| `TMPDIR` | location of the run directory (`proxhawk-tui.XXXXXX`, removed on exit) |
| `PROXHAWK_TUI_PLUGINS` | enabled plugins, overrides `plugins` |
| `PROXHAWK_TUI_USER` | Proxmox VE user to run as, overrides `user` |
| `PROXHAWK_TUI_RECORD=DIR` | records every API answer in DIR (for `backend = replay`) |
| `PROXHAWK_TUI_REPLAY=DIR` | answers used by `backend = replay` |
| `PROXHAWK_TUI_NOW=EPOCH` | frozen clock (screen tests) |
| `XDG_STATE_HOME` | location of the state file |

## Running as another user

proxhawk-tui runs as root on the node and acts by default as `root@pam` (or as
`<sudo user>@pam` when it was started with `sudo` and that user exists). At
start-up it asks which Proxmox VE user to run as (`ask_user`), or takes
`--user name@realm` / `user = name@realm`. The header shows that user.

The user's permissions then apply exactly as in the web UI: every API call
is checked with the same function as the API server
(`check_api2_permissions`), lists are filtered for the user (tree, users,
storage...), refused calls show the Proxmox VE message (`Permission check
failed (/nodes/pve1, Sys.Audit)`), and tasks are logged under the user's
name. Consoles need `VM.Console` (guests) or `Sys.Console` (node shell),
running a command in a container needs `VM.Console`, and installing
community scripts needs `root@pam`.

No password is asked: whoever runs proxhawk-tui is already root on the node.
The feature limits what proxhawk-tui does (delegated administration, checking
the rights of a user); it is not a security boundary against root.

## Plugins

Plugins are bash files in `plugins/` (or `~/.config/proxhawk-tui/plugins/`) that add
menu entries or toolbar buttons. Enable them in `F4` › Plugins (`Space` ticks
a plugin, `Enter` validates; proxhawk-tui offers to restart, keeping the current
selection, since plugins are loaded at start-up) or with `plugins = name name`. Bundled plugins:

| Plugin | Adds |
|--------|------|
| `community-scripts` | Node › *Community Scripts*: browse the [community-scripts](https://github.com/community-scripts/ProxmoxVE) catalogue (CT, VM, tools) and run an install script on the node after confirmation (needs Internet access) |
| `ansible-inventory` | Datacenter › *Ansible Inventory*: YAML inventory of the guests grouped by node, type, status and tag; `s` saves it to a file (folders created, confirmation before replacing), `v` opens it in the pager |

Writing a plugin: [EXTENDING.md](EXTENDING.md#plugins).

## Icon sets

| Set | Requirements | Look |
|-----|--------------|------|
| `nerd` | a [Nerd Font](https://www.nerdfonts.com/) in the terminal | the Font Awesome icons of the web UI (server, building, desktop, cube, database...) |
| `unicode` | UTF-8 terminal | geometric shapes, box drawing, braille graphs (default) |
| `ascii` | any terminal | letters and `+-|`; graphs use `.` and `:` |

All sets use single-cell characters only, so the layout never breaks.

### Nerd Font: squares instead of icons

The icons are drawn by the **terminal on the computer you type on**, not by
the Proxmox VE node: when proxhawk-tui runs over SSH, installing a font on the node
changes nothing. Squares (or `?`) mean that the font of that terminal has no
Nerd Font glyphs. The icon menu (`F4` › Icons) shows a preview of each set
before you choose.

1. Download a Nerd Font on your computer, for example *JetBrainsMono Nerd
   Font*, *FiraCode Nerd Font* or *Hack Nerd Font*
   (<https://www.nerdfonts.com/font-downloads>), and install it (Windows:
   right click › Install for all users; macOS: Font Book; Linux:
   `~/.local/share/fonts` then `fc-cache -f`).
2. Select it in the terminal settings:
   - Windows Terminal: Settings › profile › Appearance › Font face
     (`JetBrainsMono Nerd Font`);
   - PuTTY: Window › Appearance › Font (the "Mono" variant), and Window ›
     Translation › UTF-8;
   - MobaXterm: Settings › Terminal › Font;
   - macOS Terminal / iTerm2: Profiles › Text › Font;
   - GNOME Terminal / Konsole: profile › Text / Appearance › custom font.
3. Restart proxhawk-tui, `F4` › Icons › Nerd Font (or `glyphs = nerd`, or
   `NERD_FONT=1` with `glyphs = auto`).

If the font cannot be changed (e.g. Linux console, web shell), use
`glyphs = unicode` (default) or `ascii`.

## Themes

| Theme | Description |
|-------|-------------|
| `default` | 256 colours on the terminal background; orange accent and blue selection like the web UI |
| `dark` | paints a dark background (similar to the *Proxmox Dark* web theme) |
| `light` | paints a light background (similar to the default web theme) |
| `basic` | 8 ANSI colours (Linux console, old terminals) |
| `dracula`, `nord`, `gruvbox`, `catppuccin-mocha`, `solarized-dark`, `tokyonight` | popular palettes with their own background (truecolor when available) |

Creating a theme is described in [EXTENDING.md](EXTENDING.md#themes).

## Files written by proxhawk-tui

| Path | When |
|------|------|
| `~/.config/proxhawk-tui/proxhawk-tui.conf` | settings changed from the user menu or the first run wizard |
| `~/.local/state/proxhawk-tui/state` | last selection (for `startup = last`) |
| `$TMPDIR/proxhawk-tui.XXXXXX/` | run directory (job outputs, temporary text), removed on exit |
| `/tmp/proxhawk-tui-debug.log` | only with `PROXHAWK_TUI_DEBUG=1` |
