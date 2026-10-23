# wireguard.sh

Automated WireGuard VPN server setup for Ubuntu, Debian, CentOS, and Fedora.

[![Validate site](https://github.com/eyupio/wireguard.sh/actions/workflows/validate.yml/badge.svg)](https://github.com/eyupio/wireguard.sh/actions/workflows/validate.yml)
[![Website](https://img.shields.io/badge/website-wireguard.sh-00bcd4.svg)](https://wireguard.sh)

`wireguard.sh` is a small, auditable bash installer that configures a WireGuard
VPN server and its first client in one pass. This repository also contains the
static landing page served at [wireguard.sh](https://wireguard.sh).

## Features

- One-command, interactive installation on supported Ubuntu, Debian, CentOS,
  and Fedora releases.
- Writes a ready-to-use `/etc/wireguard/wg0.conf` and enables `wg-quick@wg0`.
- Enables IPv4 forwarding and, when configured, IPv6 forwarding.
- Configures firewall and NAT rules for the VPN subnet.
- Generates a client configuration, prints a QR code, and stores the client
  file in the root user's home directory.
- Re-run the same command to add or remove clients or uninstall WireGuard.
- No account or dashboard required.

## Quick start

> [!IMPORTANT]
> Review the installer before running it. It runs as root and changes network,
> firewall, and service configuration.
> [Read `wireguard.sh` on GitHub](https://github.com/eyupio/wireguard.sh/blob/main/wireguard.sh).

Run one of the following commands as root on a server you control:

```bash
bash <(wget -q -O - https://wireguard.sh/wireguard.sh)
```

or

```bash
bash <(curl -s https://wireguard.sh/wireguard.sh)
```

The installer detects the server's public IPv4 address when possible and
prompts for it when needed. It then asks for the WireGuard port (default
`51820`), the DNS resolver, and the first client name. On hosts with IPv6, it
also configures an IPv6 tunnel address.

## Requirements

- **Operating system:** Ubuntu 18.04+, Debian 10+, CentOS 7+, or Fedora 31+.
- **Privileges:** root access; the installer checks for `EUID 0`.
- **Shell:** `bash`, not `sh`.
- **Service manager:** `systemd`.
- **Network:** a server or VPS with a public IPv4 address (or a hostname that
  resolves to one) and the chosen WireGuard UDP port reachable.
- **Clean host recommended:** the installer is designed for a fresh server. If
  `/etc/wireguard/wg0.conf` already exists, it opens the management menu
  instead of reinstalling.

## What the installer does

1. Installs `wireguard`, `qrencode`, and the firewall tooling required by the
   distribution.
2. Writes `/etc/wireguard/wg0.conf` with the server keys, listen port, and VPN
   subnet (`10.7.0.0/24`, plus `fddd:2c4:2c4:2c4::/64` when IPv6 is enabled).
3. Enables IPv4 forwarding and, when configured, IPv6 forwarding through
   `/etc/sysctl.d/30-wireguard-forward.conf`.
4. Configures firewall and NAT rules for the VPN subnet.
5. Enables and starts `wg-quick@wg0`.
6. Creates a client configuration in `~/<client>.conf` and prints its QR code.

The installer uses the host's package manager and downloads the WireGuard tools
it needs.

## Managing an existing installation

Re-run the install command. When `/etc/wireguard/wg0.conf` exists, the
installer shows the management menu:

```text
1) Add a new client
2) Remove an existing client
3) Remove WireGuard
4) Exit
```

Client configurations are written to `~/<client>.conf`. Scan the printed QR
code with the WireGuard mobile app, or import the file into a desktop client.

## Development

The landing page is plain HTML, CSS, and JavaScript with no runtime
dependencies. Static checks and browser tests run in CI on every pull request
and on pushes to `main`.

Requirements: Python 3.9+ and Node.js 20+.

```bash
# Static checks
python3 scripts/validate_site.py
npx --yes html-validate@9.7.1 index.html

# Browser smoke tests
npm ci
npx playwright install chromium
npx playwright test
```

The Playwright tests start a local static server automatically. They cover the
copy buttons, no-JavaScript rendering, the 375 px layout, source links, and
reduced-motion behavior.

### Project layout

| Path | Purpose |
| --- | --- |
| `index.html`, `index.css`, `index.js` | Static landing page |
| `wireguard.sh` | Installer served at `/wireguard.sh` |
| `scripts/validate_site.py` | Static content checks |
| `tests/` | Playwright smoke tests |
| `package.json`, `playwright.config.js` | Browser test tooling |
| `.github/workflows/validate.yml` | CI workflow |

## Contributing

Issues and pull requests are welcome. Before opening a pull request, run the
checks in [Development](#development). Keep changes focused and include a short
description of what changed and why.

## Security notes

- Run the installer only on a server you control and trust.
- Read `wireguard.sh` before piping it to `bash`.
- Treat generated client configurations and private keys as secrets.
- Keep the operating system and WireGuard packages up to date.
- Back up `/etc/wireguard/wg0.conf` and client configurations before making changes.

## License

This repository includes two license files:

- [LICENSE](LICENSE) — GNU General Public License v3.0.
- [LICENSE.md](LICENSE.md) — MIT License.

Review both files for the terms that apply to the installer and the landing page.

## Acknowledgements

- The installer builds on [Nyr/wireguard-install](https://github.com/Nyr/wireguard-install);
  see the credit at the top of `wireguard.sh`.
- [WireGuard](https://www.wireguard.com/) is the VPN protocol and tooling this
  project installs.

## Links

- Website: <https://wireguard.sh>
- WireGuard documentation: <https://www.wireguard.com/>
- WireGuard clients: <https://www.wireguard.com/install/>
- Source and issues: <https://github.com/eyupio/wireguard.sh>
