# pvetty — Command line (non-interactive)

Besides the interface, `pvetty` answers simple commands for scripts. They
use the same API access as the interface (on the local node, as the user
running the command) and print JSON (default) or a table.

```
pvetty <command> [arguments] [options]
pvetty help
```

## Commands

| Command | Description |
|---------|-------------|
| `nodes list` | nodes of the cluster (status, IP, CPU, memory, uptime) |
| `nodes show <node>` | status of a node |
| `guests list [--node N] [--status S] [--type qemu\|lxc] [--tag T]` | guests, filtered |
| `guests show <id\|name>` | status and configuration of a guest |
| `guests start\|shutdown\|stop\|reboot\|suspend\|resume <id\|name> [--no-wait]` | power actions |
| `guests exec <id\|name> <command>` | run a command: QEMU guest agent for VMs, `pct exec` for containers; output and exit code of the command |
| `guests ip <id\|name>` | IP addresses (agent, container interfaces, neighbour table) |
| `tasks list [--running] [--node N]` | recent tasks of the cluster |
| `tasks log <upid>` | log of a task |
| `tasks stop <upid>` | stop a running task |
| `storage list [--node N]` | storages |
| `storage content <node> <storage> [--type iso\|vztmpl\|backup\|images\|rootdir]` | content of a storage |
| `api get\|create\|set\|delete <path> [--param value ...]` | any API call (same syntax as `pvesh`) |

A guest is given by its VMID or its name.

## Options

| Option | Effect |
|--------|--------|
| `-o`, `--output json\|table` | output format; default `cli_output` (`json`) |
| `--no-wait` | for actions that start a task: print `{"upid": "..."}` at once instead of waiting for the end |

## Results

- **JSON**: an array of objects for lists, an object otherwise. Actions
  print `{"upid": "...", "status": "stopped", "exitstatus": "OK"}` when the
  task ends.
- **table**: aligned columns with a header line (lists and objects).
- **Errors**: `{"error": "..."}` on standard error and exit code `1`
  (failed task included); `2` for a usage error. `guests exec` exits with
  the exit code of the command.

## Examples

```bash
pvetty guests list --status running -o table
pvetty guests start 9901                      # waits for the task
upid=$(pvetty guests shutdown web1 --no-wait | sed 's/.*"upid":"\([^"]*\)".*/\1/')
pvetty tasks log "$upid"
pvetty guests exec 9902 'uptime'
pvetty api get /nodes/pve1/storage --content backup
pvetty api set /nodes/pve1/qemu/9901/config --memory 2048
```
