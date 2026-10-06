# shellcheck shell=bash
# Default theme: 256 colours, keeps the terminal background.
# Colours follow the Proxmox VE web interface (orange accent, blue selection).
TH_BG=""
TH=(
    [norm]="39"                       # regular text
    [dim]="38;5;245"                  # secondary text
    [border]="38;5;240"               # panel borders
    [title]="1"                       # panel titles
    [header]="38;5;252;48;5;236"      # top header bar
    [header_dim]="38;5;245;48;5;236"
    [logo]="1;38;5;208;48;5;236"      # "PROXMOX" logo
    [sel]="38;5;255;48;5;25"          # selected row, focused panel
    [sel_inactive]="38;5;255;48;5;239" # selected row, unfocused panel
    [btn]="38;5;252;48;5;238"         # toolbar button
    [btn_key]="1;4;38;5;255;48;5;238" # hot key inside a button
    [btn_dis]="38;5;243;48;5;236"     # disabled button
    [ok]="38;5;71"
    [warn]="38;5;214"
    [err]="38;5;203"
    [info]="38;5;75"
    [accent]="38;5;208"
    [bar_fill]="38;5;33"
    [bar_empty]="38;5;238"
    [bar_warn]="38;5;214"
    [bar_crit]="38;5;203"
    [graph1]="38;5;75"
    [graph2]="38;5;208"
    [axis]="38;5;242"
    [th]="1;38;5;250"                 # table header
    [footer]="38;5;250;48;5;236"
    [footer_key]="1;38;5;208;48;5;236"
    [tag]="38;5;16;48;5;109"
    [menu_icon]="38;5;246"
    [group]="1;38;5;250"              # menu group / section headings
)
