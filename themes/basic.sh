# shellcheck shell=bash
# Basic theme: only the 8 standard ANSI colours (linux console, old terminals).
TH_BG=""
TH=(
    [norm]="39" [dim]="2" [border]="2" [title]="1"
    [header]="30;47" [header_dim]="30;47" [logo]="1;31;47"
    [sel]="37;44;1" [sel_inactive]="30;47"
    [btn]="30;47" [btn_key]="1;4;30;47" [btn_dis]="2"
    [ok]="32" [warn]="33" [err]="31" [info]="36" [accent]="33"
    [bar_fill]="34" [bar_empty]="2" [bar_warn]="33" [bar_crit]="31"
    [graph1]="36" [graph2]="33" [axis]="2" [th]="1;4"
    [footer]="30;47" [footer_key]="1;31;47" [tag]="30;46"
    [menu_icon]="2" [group]="1"
)
