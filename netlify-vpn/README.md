# Netlify VLESS VPN (Deno Edge Functions)

This project deploys a VLESS WebSocket VPN serverless node using **Netlify Edge Functions** (running on Deno).

## Features
- **Protocol:** VLESS
- **Transport:** WebSocket + TLS
- **Deployment:** Netlify (Serverless/Edge)
- **Frontend:** Simple dashboard to generate VLESS links and QR Codes.

## Limitations
- **Protocols:** Only supports **VLESS + WebSocket**. XTLS, VMess, Trojan, and Raw TCP are **not** supported on Netlify.
- **UDP:** **Not Supported.** Netlify Edge Functions only allow TCP connections (`Deno.connect`). UDP traffic (e.g., QUIC, DNS over UDP) will be blocked.
- **Performance:** Subject to Netlify Edge Function limits (execution time, memory). Not recommended for heavy streaming or torrenting.

## How to Deploy

### Option 1: Netlify Drop (Quickest)
Since this uses Edge Functions, "Drag and Drop" might not configure the functions correctly without a Git repo. **We recommend Option 2.**

### Option 2: Connect to Git (Recommended)
1.  **Fork/Clone** this repository to your GitHub/GitLab.
2.  Log in to [Netlify](https://app.netlify.com/).
3.  Click **"Add new site"** -> **"Import from an existing project"**.
4.  Select your repository.
5.  Netlify should detect the `netlify.toml` automatically.
    - **Base directory:** `netlify-vpn` (Important! Since the files are in this subfolder).
    - **Publish directory:** `public`
    - **Functions directory:** `netlify/edge-functions`
6.  **Environment Variables:**
    - Go to **Site Settings** -> **Environment variables**.
    - Add a variable named `UUID`.
    - Value: Generate a random UUID (e.g., using an online generator or `uuidgen`).
    - *If you don't set this, the default UUID is:* `8f91b6a0-e8ee-4497-b08e-8e9935147575`
7.  **Deploy**.

## How to Connect
1.  Open your deployed site URL (e.g., `https://your-site.netlify.app`).
2.  Enter the UUID you configured (or leave default).
3.  Click **Generate Configuration**.
4.  Copy the **VLESS Link** or scan the **QR Code** using your VPN client.

### Supported Clients
- **Android:** V2RayNG, NekoBox
- **iOS:** Shadowrocket, V2Box
- **PC:** V2RayN, NekoRay

## Project Structure
- `netlify.toml`: Configuration file.
- `netlify/edge-functions/vpn.ts`: The Deno script that handles VLESS traffic.
- `public/index.html`: The frontend dashboard.
