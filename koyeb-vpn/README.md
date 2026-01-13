# Koyeb Xray VPN (Docker)

This project deploys a full-featured VPN node (Xray-core) on **Koyeb** using Docker.

## Features
- **Protocols:**
  - **VLESS** + WebSocket + TLS
  - **VMess** + WebSocket + TLS
  - **Trojan** + WebSocket + TLS
- **Dashboard:** A web-based dashboard to view your `UUID` and generate connection links (QR Code/Text).
- **Security:** Dashboard protected by HTTP Basic Auth.
- **Architecture:** `Nginx` (Frontend/Proxy) -> `Xray` (Backend).

## Deployment Guide (Koyeb)

1.  **Fork** this repository to your GitHub.
2.  Login to [Koyeb](https://app.koyeb.com/).
3.  Click **Create App**.
4.  Select **GitHub** as the deployment method.
5.  Select this repository.
6.  **Builder:** `Dockerfile` (default).
7.  **Environment Variables** (Optional):
    - `UUID`: Your VPN secret. (Default: Randomly generated)
    - `DASH_USER`: Dashboard username. (Default: `admin`)
    - `DASH_PASS`: Dashboard password. (Default: Same as `UUID`)
8.  **Exposed Ports:**
    - Port `8000` (HTTP). *Koyeb will map this to HTTPS (443) automatically.*
9.  **Deploy**.

## How to Use
1.  Open your App URL (e.g., `https://my-app.koyeb.app`).
2.  **Login:**
    - User: `admin` (or what you set in `DASH_USER`)
    - Pass: Your `UUID` (or what you set in `DASH_PASS`)
    - *Note: Check build logs if you used a random UUID.*
3.  Copy the **VLESS / VMess / Trojan** links.
4.  Import the link into your client (v2rayNG, NekoBox, Shadowrocket, etc.).

## Troubleshooting
- **Connection Failed?** Ensure your client has `TLS` enabled (SNI = your app domain).
- **Forgot Password?** Check the Koyeb "Runtime Logs" to see the generated UUID/Password at startup.
