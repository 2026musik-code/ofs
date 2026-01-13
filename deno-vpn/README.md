# Deno VLESS & Trojan VPN

This project implements a lightweight VPN node using **Deno**. It supports VLESS and Trojan protocols over WebSocket, suitable for deployment on **Deno Deploy** or any server with Deno installed.

## Features
- **Protocols**: VLESS, Trojan
- **Transport**: WebSocket (Secure via TLS on Deno Deploy)
- **Dashboard**: Web interface to generate configuration links and QR codes.
- **Login**: Simple UUID-based access control to the dashboard.

## Prerequisites
- A [Deno Deploy](https://deno.com/deploy) account OR a VPS with [Deno installed](https://deno.land/#installation).
- A domain name (optional, Deno Deploy provides `deno.dev` subdomains).

## Deployment

### Option A: Deno Deploy (Recommended)
1.  **Fork** this repository.
2.  Go to **Deno Deploy Dashboard**.
3.  **New Project** -> Select your repository.
4.  **Entry Point**: Select `main.ts`.
5.  **Environment Variables**:
    - `UUID`: Your secret UUID (Password). Generate one locally.
    - `TROJAN_PASSWORD`: (Optional) Password for Trojan. Defaults to `UUID`.
6.  **Deploy**.

### Option B: VPS / Local
1.  Install Deno: `curl -fsSL https://deno.land/x/install/install.sh | sh`
2.  Clone this repo.
3.  Start the server:
    ```bash
    deno task start
    ```
    Or manually:
    ```bash
    UUID="your-uuid" deno run --allow-net --allow-read --allow-env main.ts
    ```
4.  Use a reverse proxy (Caddy/Nginx) to handle TLS if running on a VPS.

## Usage
1.  Open your deployed URL (e.g., `https://my-vpn.deno.dev`).
2.  Enter your `UUID` to login.
3.  Select Protocol (**VLESS** or **Trojan**).
4.  Generate and copy the link to your client (v2rayNG, Shadowrocket, etc.).

## Limitations
- **UDP**: Not supported (Deno generic socket API limitation).
- **XTLS**: Not supported (Requires raw TCP direct access).
- **TCP**: Outbound only. Inbound is WebSocket.
