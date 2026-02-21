# Grafana Alloy for Home Assistant

Ship Home Assistant OS logs to a remote [Loki](https://grafana.com/oss/loki/) instance using [Grafana Alloy](https://grafana.com/docs/alloy/latest/).

This add-on replaces the deprecated Promtail add-on, which is incompatible with modern HAOS versions (11+) due to systemd 252+ compact journal format changes.

## Configuration

### Required

- **loki_url**: The full URL to your Loki push endpoint (e.g., `http://192.168.1.45:3100/loki/api/v1/push`)

### Optional

- **log_level**: Alloy log verbosity (`debug`, `info`, `warn`, `error`). Default: `info`
- **additional_config**: Extra Alloy config blocks to append (advanced users)

## Labels

All journal entries are shipped to Loki with these labels:

| Label | Source |
|-------|--------|
| `job` | `systemd-journal` (static) |
| `unit` | systemd unit name |
| `hostname` | machine hostname |
| `syslog_identifier` | process identifier |
| `transport` | journal transport type |
| `container_name` | Docker container name (for add-ons) |
| `level` | log priority (debug, info, warning, error, etc.) |

## Debug UI

The Alloy debug UI is available at `http://<haos-ip>:12345` when the add-on is running. Use it to inspect component health, view the pipeline DAG, and troubleshoot issues.

## Advanced: Additional Config

The `additional_config` option lets you append raw Alloy config blocks. For example, to also scrape a file:

```
local.file_match "extra" { path_targets = [{__path__ = "/config/home-assistant.log"}] }
loki.source.file "extra" { targets = local.file_match.extra.targets forward_to = [loki.write.loki.receiver] }
```

Note: This is injected as-is into the config file. Syntax errors will prevent Alloy from starting.

## Troubleshooting

- **No logs in Loki**: Check that `loki_url` is reachable from HAOS. Try `ping <loki-host>` from the SSH add-on.
- **Add-on crashes on start**: Check the add-on log for Alloy config errors. Set `log_level: debug` for verbose output.
- **"timestamp too old" in Loki**: Normal on first start. Alloy reads the full journal history; Loki rejects entries outside its retention window. Resolves in 1-2 minutes.

## Support

Report issues at: https://github.com/ecohash-co/ha-addon-alloy/issues
