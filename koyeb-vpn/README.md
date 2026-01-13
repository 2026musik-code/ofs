# Universal Xray VPN (Koyeb / VPS)

This project deploys a full-featured VPN node (Xray-core) using Docker. It is optimized for **Koyeb** but works perfectly on any **VPS**.

## Features
- **Protocols:** VLESS, VMess, Trojan (WebSocket + TLS).
- **Dashboard:** Web interface to manage credentials (protected by Basic Auth).
- **Architecture:** Nginx (Proxy) -> Xray (Core).

---

## Option 1: Deploy on Koyeb (Serverless)
1.  **Fork** this repository.
2.  Create a new App on [Koyeb](https://app.koyeb.com/).
3.  Select **GitHub** source -> This repo.
4.  **Builder:** Dockerfile.
5.  **Env Vars:** `UUID`, `DASH_USER`, `DASH_PASS` (Optional).
6.  **Deploy**.
7.  *SSL is automatic on Koyeb.*

---

## Option 2: Deploy on VPS (Docker)
Works on Ubuntu, Debian, CentOS, etc.

### 1. Install Docker
```bash
curl -fsSL https://get.docker.com | sh
```

### 2. Clone & Run
```bash
git clone <your-repo-url> vpn
cd vpn/koyeb-vpn
```

### 3. Start (HTTP Only)
By default, this runs on Port 80.
```bash
docker compose up -d
```
*Note: Without a domain and SSL certificate, clients must use `allowInsecure: true` or `encryption: none`.*

### 4. Enable HTTPS (Recommended)
To get real TLS (SSL), use **Caddy** as a reverse proxy in front of Docker.

1.  **Install Caddy:** [Instructions](https://caddyserver.com/docs/install)
2.  **Configure Caddyfile:**
    ```caddy
    your-domain.com {
        reverse_proxy localhost:80
    }
    ```
3.  **Run Caddy:** `caddy run`
4.  Now your VPN works over `https://your-domain.com`.

---

## Configuration Variables
| Variable | Description | Default |
|----------|-------------|---------|
| `UUID` | Main VPN Secret | Random Generated |
| `DASH_USER` | Dashboard Username | `admin` |
| `DASH_PASS` | Dashboard Password | Same as UUID |

## Troubleshooting
- **Logs:** `docker logs -f xray-vpn` (VPS) or Runtime Logs (Koyeb).
- **Time Sync:** Xray requires correct server time. Ensure your VPS time is synced.
