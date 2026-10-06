# Notes for coding agents

pvetty is a bash 5 terminal interface for Proxmox VE (plus a small Perl
API helper). Read these before changing code:

- `docs/DEVELOPMENT.md` — design decisions, Proxmox VE behaviours, lessons
  learned (bash pitfalls of this code base), release procedure.
- `docs/ARCHITECTURE.md` — modules, main loop, rendering, API layer.
- `docs/EXTENDING.md` — adding panels, CRUD tables, forms, plugins.
- `docs/TESTING.md` — test tools.

## Rules

- English everywhere (code, comments, docs); user strings go through `T` /
  `Tf` (i18n), then `tools/i18n-extract.sh` regenerates `lang/TEMPLATE.sh`.
- Minimal footprint: only what a Proxmox VE node ships (bash, Perl and the
  PVE modules, pvesh, whiptail/dialog, less). No new dependency.
- Match the surrounding style: `REPLY` for function results, `local` for
  every variable (a local named like a global, e.g. `L`, shadows it).
- Write tests only against test guests (VMID 9901-9919) and test disks; never
  touch other guests of the node.

## Checks

```
tools/lint.sh             # bash -n, perl -c, shellcheck (pre-commit hook)
tools/selftest.sh         # every panel renders (read only)
tools/screen-test.sh      # golden screens on recorded API answers (tmux)
tools/integration-test.sh # read/write tests on a real node (test guests)
```

Enable the hook once per clone: `git config core.hooksPath .githooks`.
Work on the `develop` branch; `main` gets the tagged releases.
