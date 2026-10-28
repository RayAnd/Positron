# Security Policy

## Supported Versions

| Version | Supported |
| :--- | :--- |
| `2.1.x` | :white_check_mark: |
| `2.0.x` | :white_check_mark: |
| `< 2.0` | :x: |

## Scope & Security Model

Positron operates entirely locally on your Mac:
- It contains **no telemetry, analytics, or remote servers**.
- `positron-steam.dylib` is injected locally into `/Applications/Steam.app` only when the user explicitly clicks **Enable Positron in Steam** (and can be removed at any time via **Restore Stock Steam**).
- `compat_run.sh` and `PositronCore` validate paths, avoid following untrusted symlinks in prefix locks/templates, and sanitize shell arguments.

## Reporting a Vulnerability

If you discover a security vulnerability (such as arbitrary command injection via crafted `.acf`/`.vdf` manifests or unsafe symlink traversal in prefix setup):

1. Please use [**GitHub Private Vulnerability Reporting**](https://github.com/RayAnd/Positron/security/advisories/new) on this repository rather than opening a public issue.
2. Include steps to reproduce and the affected component (`steam-bridge`, `compat_run.sh`, `runner-supervisor`, or `PositronCore`).
3. You will receive an acknowledgment within 72 hours.
