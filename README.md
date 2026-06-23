# 3X-UI-Installer

## Project scope and operational boundaries

This project was created primarily for my own use and is published as-is.

It is focused on one narrow 3x-ui installer workflow, not on becoming a universal proxy management stack, a full panel replacement, or a general support product.

Feature requests, custom setup requests, and general support requests may be ignored.

The goal is to keep the installer small, predictable, and focused on the setup it actually automates:

* install and configure a minimal but sufficient 3x-ui setup;
* use a clean VPS as the expected deployment target;
* avoid broad compatibility layers for unrelated proxy workflows;
* avoid preserving or merging with existing production 3x-ui, Nginx, UFW, or custom proxy stacks;
* keep the install flow readable and maintainable.

Important boundaries:

* install mode may overwrite installer-managed configuration;
* uninstall mode is destructive and intended for clean VPS rollback;
* existing 3x-ui database content is not migrated;
* existing custom Nginx/UFW state is not preserved;
* Let's Encrypt certificate and Certbot account directories are preserved;
* the project is currently in active development, so the `main` branch install command tracks the latest code.

If you need a universal proxy management stack with many client profiles, extra routing presets, multiple panel modes, existing production data migration, or broad compatibility layers, this project may not be the right tool.

---

## Overview

Bash installer for a clean 3x-ui VPS setup with:

* 3x-ui by MHSanaei https://github.com/MHSanaei/3x-ui
* Nginx SNI stream routing
* selectable installation profiles
* VLESS + TCP + REALITY inbound
* VLESS + XHTTP inbound
* optional separate XHTTP REALITY SNI/domain profile
* subscription endpoint
* fake fallback sites
* post-install smoke checks
* full uninstall mode for clean VPS rollback

The installer supports only **3x-ui v3.0.0 and newer**.

The installer is designed for a **clean VPS**.
It is not intended as an in-place migration tool for an existing production 3x-ui installation.

---

## Supported systems

Supported:

* Debian 12
* Ubuntu 24.04

Required:

* root access
* public IPv4
* DNS A records pointing to the VPS IPv4
* two or three domains/subdomains, depending on the selected profile

Optional:

* public IPv6
* DNS AAAA records

If AAAA records exist, they must point to the VPS IPv6.

---

<details>
<summary><strong>DNS requirements</strong></summary>

## DNS requirements

The required number of public domains depends on the selected installation profile.

### Standard profile — 2 domains

| Purpose | Example |
| ------- | ------- |
| Panel, subscription, fake site | `panel.example.com` |
| TCP REALITY, XHTTP, fake site | `reality.example.com` |

Minimum DNS records:

```text
panel.example.com    A      VPS_IPV4
reality.example.com  A      VPS_IPV4
```

Optional IPv6 records:

```text
panel.example.com    AAAA   VPS_IPV6
reality.example.com  AAAA   VPS_IPV6
```

### Separate XHTTP SNI profile — 3 domains

| Purpose | Example |
| ------- | ------- |
| Panel, subscription, fake site | `panel.example.com` |
| TCP REALITY, fake site | `reality.example.com` |
| XHTTP REALITY, fake site | `xhttp.example.com` |

Minimum DNS records:

```text
panel.example.com    A      VPS_IPV4
reality.example.com  A      VPS_IPV4
xhttp.example.com    A      VPS_IPV4
```

Optional IPv6 records:

```text
panel.example.com    AAAA   VPS_IPV6
reality.example.com  AAAA   VPS_IPV6
xhttp.example.com    AAAA   VPS_IPV6
```

Rules:

* A records are required.
* AAAA records are optional.
* If AAAA records exist, they must match the detected VPS IPv6.
* All domains used by the selected profile must be different.

</details>

---

<details>
<summary><strong>Installation</strong></summary>

## Installation

Run as root on a clean VPS.

<details>
<summary><strong>Root access</strong></summary>

## Root access

The installer must be run as root.

If your VPS allows direct root login, connect as root and run the installer command.

If your VPS provides a regular user with sudo privileges instead of direct root login, start a root shell first:

```bash
sudo -i
```

Check that the current shell is root:

```bash
whoami
```

Expected output:

```text
root
```

Then run the installer command.

Do not use `sudo bash <(curl ...)` as the recommended method. Use `sudo -i` first, then run the installer from the root shell.

</details>

<details>
<summary><strong>Clean VPS model</strong></summary>

## Clean VPS model

This installer is intended for a fresh server.
Do not run it over an important existing production 3x-ui setup unless you understand exactly what will be replaced.
Before using it on a non-empty VPS, make backups manually.

Recommended backup items:

```text
/etc/nginx/
/usr/local/x-ui/
/etc/x-ui/
/etc/letsencrypt/
/etc/systemd/system/x-ui.service
/var/www/html/
```

</details>

<details>
<summary><strong>Minimal Debian prerequisites</strong></summary>

### Minimal Debian prerequisites

On a minimal Debian installation, `curl` may not be installed by default.

Install `curl` and CA certificates first:

```bash
apt update && apt install -y curl ca-certificates
```

</details>

Recommended one-command install:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/AndrewZAP1977/3x-ui-installer/main/install.sh)
```

This starts the interactive installer flow.

One-command install with custom domains/subdomains:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/AndrewZAP1977/3x-ui-installer/main/install.sh) \
    --domain panel.example.com \
    --reality-domain reality.example.com
```

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/AndrewZAP1977/3x-ui-installer/main/install.sh) \
    --profile separate-xhttp-sni \
    --domain panel.example.com \
    --reality-domain reality.example.com \
    --xhttp-domain xhttp.example.com
```

Example with automatic generated subdomains:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/AndrewZAP1977/3x-ui-installer/main/install.sh) \
    --auto-domain
```

`--auto-domain` uses the public third-party `cdn-one.org` wildcard DNS pattern.
This domain is not controlled by this installer project.

Auto-domain mode is intended for testing, disposable VPS deployments, and quick experiments.
For long-lived or production installations, use your own domains.

For the `standard` profile, `--auto-domain` generates two domains.

For the `separate-xhttp-sni` profile, `--auto-domain` generates three domains:
panel domain, TCP REALITY domain, and XHTTP REALITY domain.

Example with pinned 3x-ui version:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/AndrewZAP1977/3x-ui-installer/main/install.sh) \
    --domain panel.example.com \
    --reality-domain reality.example.com \
    --xui-version v3.3.1
```

Show help:

The bootstrap loader downloads the full project into:

```text
/root/3x-ui-installer
```

Raw GitHub execution uses the bootstrap loader and must be run from a root shell.

Show help after bootstrap or from a local checkout:

```bash
bash /root/3x-ui-installer/install.sh --help
```

If you cloned the repository manually, help can also be shown from the repository directory:

```bash
bash install.sh --help
```

<details>
<summary><strong>Installation profiles</strong></summary>

## Installation profiles

The installer supports two installation profiles.

### `standard`

Default 2-domain setup.

```text
panel.example.com    -> panel, subscription, fake site
reality.example.com  -> TCP REALITY, XHTTP, fake site
```

Use this profile if you do not need a separate XHTTP domain.

### `separate-xhttp-sni`

3-domain setup with a separate XHTTP REALITY SNI/domain.

```text
panel.example.com    -> panel, subscription, fake site
reality.example.com  -> TCP REALITY, fake site
xhttp.example.com    -> XHTTP REALITY, fake site
```

Use this profile if you want XHTTP REALITY to have its own public domain and SNI.

</details>

<details>
<summary><strong>Installer options</strong></summary>

## Installer options

| Option                                       | Description                                                |
| -------------------------------------------- | ---------------------------------------------------------- |
| `-h`, `--help`                               | Show help for local script usage. Raw GitHub execution still requires root. |
| `-profile`, `--profile PROFILE`              | Select installation profile: `standard` or `separate-xhttp-sni`. |
| `-domain`, `--domain DOMAIN`                 | Panel domain.                                              |
| `-reality-domain`, `--reality-domain DOMAIN` | TCP REALITY domain. In the `standard` profile, this domain also carries the XHTTP inbound. |
| `-xhttp-domain`, `--xhttp-domain DOMAIN` | XHTTP REALITY domain for the `separate-xhttp-sni` profile. Must be different from panel and reality domains. |
| `-auto-domain`, `--auto-domain`              | Generate temporary domains automatically using third-party `cdn-one.org` DNS. Intended only for testing, disposable VPS deployments, and quick experiments. In the `separate-xhttp-sni` profile, this also generates the XHTTP domain. |
| `-xui-version`, `--xui-version VERSION`      | 3x-ui version to install. Default: `latest`.               |
| `-uninstall`, `--uninstall`                  | Remove installed components, generated files, and installer directory. |

Supported 3x-ui version format:

```text
latest
v3.3.1
3.3.1
```

Versions below v3 are blocked intentionally because older 3x-ui releases use different API and configuration formats.

</details>

<details>
<summary><strong>What the installer creates</strong></summary>

## What the installer creates

The installer creates:

* 3x-ui panel settings
* TCP REALITY inbound
* XHTTP inbound
* one default client
* subscription endpoint
* Nginx SNI stream routing
* fake websites for all public domains used by the selected profile

At the end, the installer prints:

* panel username
* panel password
* panel URL
* subscription URL
* fake site URLs

Save the final output after installation.

</details>

<details>
<summary><strong>Fake sites</strong></summary>

## Fake sites

Fake sites are deployed automatically.
They are used as fallback web content for non-panel and non-proxy paths.

Expected behavior for the `standard` profile:

```text
https://panel.example.com/
https://reality.example.com/
```

Expected behavior for the `separate-xhttp-sni` profile:

```text
https://panel.example.com/
https://reality.example.com/
https://xhttp.example.com/
```

All public domains used by the selected profile should open normal-looking fake websites.

</details>

</details>

---

<details>
<summary><strong>Uninstall</strong></summary>

## Uninstall

The installer includes a destructive uninstall mode for clean VPS rollback.

Uninstall is intended for servers where this installer owns the 3x-ui, Nginx, UFW, and related setup. Do not use it on a VPS where you need to preserve existing custom Nginx configuration, UFW rules, shared packages, or an existing production 3x-ui database.

Recommended one-command uninstall:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/AndrewZAP1977/3x-ui-installer/main/install.sh) --uninstall
```

Manual local uninstall after bootstrap:

```bash
bash /root/3x-ui-installer/install.sh --uninstall
```

Do not run uninstall from inside `/root/3x-ui-installer` if you want to avoid ending the shell session in a deleted working directory.

Uninstall mode is intended for servers where this installer was used on a clean VPS.

It removes:

* 3x-ui service and files
* Xray files installed by 3x-ui
* generated Nginx configuration
* generated fake sites
* randomfakehtml repository
* Certbot webroot challenge directory
* Nginx package and configuration
* Certbot package
* UFW rules and UFW package
* generated runtime leftovers
* installer-created temporary files
* downloaded installer directory

It does not attempt to create a full system backup or migrate existing 3x-ui data. If you need to preserve an existing panel, export or back up the 3x-ui database before running install or uninstall.

It preserves Let's Encrypt certificates and Certbot account data:

```text
/etc/letsencrypt
/var/lib/letsencrypt
/var/log/letsencrypt
```

This helps avoid losing existing certificates and prevents unnecessary certificate re-issuance during repeated installs.

It keeps basic system packages that are commonly expected to remain available:

```text
bash
sudo
python3
curl
ca-certificates
openssl
iproute2
```

Uninstall mode is destructive.
Do not run it on a server where Nginx, Certbot, UFW, or 3x-ui are used for anything unrelated to this installer.

</details>

---

<details>
<summary><strong>Firewall</strong></summary>

## Firewall

The installer enables UFW and allows:

| Port              | Protocol | Purpose                                             |
| ----------------- | -------- | --------------------------------------------------- |
| detected SSH port | TCP      | SSH access                                          |
| 80                | TCP      | HTTP challenge / redirect                           |
| 443               | TCP      | public HTTPS / SNI stream                           |
| 443               | UDP      | reserved for future QUIC/Hysteria2-style transports |

The installer does not currently create UDP listeners.
UDP 443 is allowed only as a reserved future rule.

</details>

---

<details>
<summary><strong>Post-install smoke checks</strong></summary>

## Post-install smoke checks

After provisioning, the installer runs smoke checks.

It verifies:

* Nginx service is active
* x-ui service is active
* `nginx -t` passes
* required TCP listeners exist
* standard profile: XHTTP Unix socket exists
* separate XHTTP SNI profile: XHTTP REALITY TCP listener exists
* fake sites open
* panel URL opens
* subscription URL opens

If a smoke check fails, the installer stops and prints the failed check.

</details>

---

<details>
<summary><strong>Notes</strong></summary>

## Notes

<details>
<summary><strong>Auto-domain mode</strong></summary>

## Auto-domain mode

Auto-domain mode generates temporary domains using the public third-party `cdn-one.org` wildcard DNS pattern:

```text
<IPv4>.cdn-one.org
<IPv4-with-dashes>.cdn-one.org
x-<IPv4-with-dashes>.cdn-one.org
```

This pattern is also known from public x-ui-pro/mozaroc-style auto-domain examples (https://github.com/mozaroc/x-ui-pro), but this installer project does not claim ownership or operational control over `cdn-one.org`.

This installer project does not control the `cdn-one.org` domain or its DNS infrastructure.

Availability, DNS behavior, and certificate issuance reliability depend on the third-party `cdn-one.org` domain and its current DNS setup.

Use auto-domain mode only for testing, disposable VPS deployments, and quick experiments.

For long-lived or production installations, use your own domains.

</details>

<details>
<summary><strong>XHTTP transport note</strong></summary>

## XHTTP transport note

XHTTP behavior depends on the selected profile.

In the `standard` profile, XHTTP shares the Reality domain.

In the `separate-xhttp-sni` profile, XHTTP REALITY uses its own public domain/SNI and its own fake-site fallback backend.

XHTTP is more client-sensitive than TCP REALITY, especially on router-based clients.
In this project, TCP REALITY is treated as the primary fast transport, while XHTTP REALITY is treated as an additional web-like fallback/alternative transport.

For XHTTP REALITY, the generated client must not use `xtls-rprx-vision` flow.
The XHTTP REALITY client flow is intentionally empty.

</details>

<details>
<summary><strong>Let's Encrypt renewal configs</strong></summary>

## Let's Encrypt renewal configs

The installer uses Certbot webroot HTTP-01 validation with:

```text
/var/www/letsencrypt
```

If an existing Let's Encrypt certificate is reused, the installer checks the matching Certbot renewal config for the current installation domain.

If an older standalone, nginx, or non-target webroot renewal config is found, it is rewritten to the installer target webroot scheme and backed up first.

Backups are stored under:

```text
/root/3x-ui-installer-renewal-backups/
```

Only renewal configs for domains used by the current installation are touched.

</details>

<details>
<summary><strong>Security notes</strong></summary>

## Security notes

The installer tries to keep public exposure minimal:

* 3x-ui panel is not exposed directly.
* subscription listener is bound to localhost.
* panel access is routed through Nginx.
* TCP REALITY and separate XHTTP REALITY inbounds listen locally behind Nginx stream SNI routing.
* unknown or missing SNI traffic is routed away from the panel backend.
* generated secrets are random.
* unsupported 3x-ui v2.x versions are blocked.

</details>

</details>

---

<details>
<summary><strong>Troubleshooting</strong></summary>

## Troubleshooting

Check services:

```bash
systemctl status nginx --no-pager
systemctl status x-ui --no-pager
```

Check listeners:

```bash
ss -ltnp
ss -lxnp
```

Check Nginx config:

```bash
nginx -t
```

Check recent logs:

```bash
journalctl -u nginx -n 100 --no-pager
journalctl -u x-ui -n 100 --no-pager
```

Check DNS:

```bash
dig +short A panel.example.com
dig +short A reality.example.com
dig +short A xhttp.example.com
dig +short AAAA panel.example.com
dig +short AAAA reality.example.com
dig +short AAAA xhttp.example.com
```

Check local SNI routing:

```bash
curl -skL --resolve panel.example.com:443:127.0.0.1 https://panel.example.com/
curl -skL --resolve reality.example.com:443:127.0.0.1 https://reality.example.com/
curl -skL --resolve xhttp.example.com:443:127.0.0.1 https://xhttp.example.com/
```

</details>

---

## License

This project is an installer/wrapper around external components.

External projects keep their own licenses:

* 3x-ui by MHSanaei
* Nginx
* Certbot
* fake sites repository
