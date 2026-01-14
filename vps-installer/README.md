# VPS Auto-Installer: Xray VPN (VLESS, VMess, Trojan)

This script automatically installs and configures a full-featured VPN node on your **Ubuntu 20.04/22.04** or **Debian 10/11** VPS.

## Features
- **Protocols:** VLESS, VMess, Trojan (WebSocket + TLS).
- **Web Dashboard:** Manage and view your config links securely.
- **Auto SSL:** Automatically obtains an SSL certificate using Let's Encrypt.
- **Security:** Nginx Reverse Proxy with Basic Auth protection for the dashboard.

## Installation

1.  **Connect to your VPS** (via SSH).
2.  **Run the following command:**

```bash
apt update && apt install -y git && \
git clone https://github.com/YOUR_REPO/vps-installer.git && \
bash vps-installer/install.sh
```

*(Replace `https://github.com/YOUR_REPO` with your actual repository URL)*

3.  **Follow the prompts:**
    - Enter your domain name (e.g., `vpn.mydomain.com`).
    - *Make sure the domain is already pointed to your VPS IP address!*

## Post-Installation
After the script finishes, you will see your credentials:
- **Dashboard URL:** `https://your-domain.com`
- **Username:** `admin`
- **Password:** (Your generated UUID)

## Manual Actions
- **Renew SSL:** Certbot usually sets up a cron job, but you can force renew with `certbot renew`.
- **Change UUID:** Edit `/usr/local/etc/xray/config.json`, then restart Xray: `systemctl restart xray`.
