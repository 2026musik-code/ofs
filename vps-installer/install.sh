#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# Check Root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root!${PLAIN}"
   exit 1
fi

echo -e "${GREEN}Starting VPS VPN Auto-Installer...${PLAIN}"

# 1. System Update & Dependencies
echo -e "${YELLOW}[1/6] Updating System & Installing Dependencies...${PLAIN}"
apt update && apt install -y curl wget git nginx certbot python3-certbot-nginx unzip uuid-runtime apache2-utils qrencode

# 2. Input Domain
echo -e "${YELLOW}[2/6] Configuration${PLAIN}"
read -p "Enter your domain name (e.g., vpn.example.com): " DOMAIN

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Error: Domain is required!${PLAIN}"
    exit 1
fi

# 3. Install Xray Core
echo -e "${YELLOW}[3/6] Installing Xray-Core...${PLAIN}"
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# 4. Configure Xray
echo -e "${YELLOW}[4/6] Configuring Xray...${PLAIN}"
UUID=$(uuidgen)
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": 10001,
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "$UUID" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vless" }
      }
    },
    {
      "port": 10002,
      "protocol": "vmess",
      "settings": {
        "clients": [ { "id": "$UUID" } ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vmess" }
      }
    },
    {
      "port": 10003,
      "protocol": "trojan",
      "settings": {
        "clients": [ { "password": "$UUID" } ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/trojan" }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom" },
    { "protocol": "blackhole", "tag": "block" }
  ]
}
EOF

# Restart Xray
systemctl restart xray
systemctl enable xray

# 5. Configure Nginx & Dashboard
echo -e "${YELLOW}[5/6] Setting up Nginx & Dashboard...${PLAIN}"

# Dashboard
mkdir -p /var/www/vpanel
# Download Dashboard Template (In real scenario, we would download from the repo, but here we write it inline for the script to be standalone or assume files exist)
# Since I'm creating the script in the repo, I will assume the user cloned the repo OR I will embed the HTML content.
# Embedding is safer for a single-file installer feel, but checking if file exists is better for development.
# I'll use cat for embedding the dashboard template logic here to make the script robust.

cat > /var/www/vpanel/index.html <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Xray VPN Panel</title>
    <script src="https://cdn.jsdelivr.net/npm/qrcode@1.4.4/build/qrcode.min.js"></script>
    <style>
        :root { --primary: #007bff; --bg: #f8f9fa; }
        body { font-family: sans-serif; background: var(--bg); padding: 20px; display: flex; flex-direction: column; align-items: center; }
        .card { background: white; padding: 2rem; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); max-width: 600px; width: 100%; }
        h1 { color: var(--primary); text-align: center; }
        textarea { width: 100%; height: 100px; margin-bottom: 10px; border: 1px solid #ddd; padding: 10px; border-radius: 4px; }
        button { background: var(--primary); color: white; border: none; padding: 10px 20px; border-radius: 4px; cursor: pointer; width: 100%; margin-bottom: 5px; }
        button:hover { opacity: 0.9; }
        .tab-btn { background: #ddd; color: #333; width: auto; display: inline-block; }
        .tab-btn.active { background: var(--primary); color: white; }
    </style>
</head>
<body>
    <div class="card">
        <h1>VPN Dashboard</h1>
        <p><strong>Domain:</strong> <span id="host"></span></p>
        <p><strong>UUID:</strong> <span id="uuid">$UUID</span></p>

        <div style="text-align: center; margin-bottom: 20px;">
            <button class="tab-btn active" onclick="setProto('vless')">VLESS</button>
            <button class="tab-btn" onclick="setProto('vmess')">VMess</button>
            <button class="tab-btn" onclick="setProto('trojan')">Trojan</button>
        </div>

        <textarea id="link" readonly></textarea>
        <button onclick="copyLink()">Copy Link</button>
        <div id="qrcode" style="display: flex; justify-content: center; margin-top: 10px;"></div>
    </div>

    <script>
        const uuid = "$UUID";
        const host = "$DOMAIN";
        const port = "443";
        let currentProto = "vless";

        document.getElementById('host').innerText = host;

        function setProto(proto) {
            currentProto = proto;
            document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
            event.target.classList.add('active');
            generate();
        }

        function generate() {
            let link = "";
            const path = "/" + currentProto;

            if (currentProto === "vless") {
                link = \`vless://\${uuid}@\${host}:\${port}?path=\${path}&security=tls&encryption=none&type=ws&host=\${host}&sni=\${host}#\${host}-VLESS\`;
            } else if (currentProto === "trojan") {
                link = \`trojan://\${uuid}@\${host}:\${port}?path=\${path}&security=tls&type=ws&host=\${host}&sni=\${host}#\${host}-Trojan\`;
            } else if (currentProto === "vmess") {
                const vmessJson = {
                    v: "2", ps: \`\${host}-VMess\`, add: host, port: port, id: uuid, aid: "0",
                    scy: "auto", net: "ws", type: "none", host: host, path: path, tls: "tls", sni: host
                };
                link = "vmess://" + btoa(JSON.stringify(vmessJson));
            }

            document.getElementById('link').value = link;
            document.getElementById('qrcode').innerHTML = "";
            QRCode.toCanvas(link, { width: 200 }, (err, canvas) => {
                if(!err) document.getElementById('qrcode').appendChild(canvas);
            });
        }

        generate(); // Init

        function copyLink() {
            const el = document.getElementById('link');
            el.select();
            document.execCommand('copy');
            alert("Copied!");
        }
    </script>
</body>
</html>
HTML

# Basic Auth for Dashboard
DASH_USER="admin"
DASH_PASS="$UUID" # Default password is UUID
htpasswd -bc /etc/nginx/.htpasswd "$DASH_USER" "$DASH_PASS"

# Nginx Config
cat > /etc/nginx/sites-available/vpn <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    root /var/www/vpanel;
    index index.html;

    location / {
        auth_basic "VPN Admin Area";
        auth_basic_user_file /etc/nginx/.htpasswd;
        try_files \$uri \$uri/ /index.html;
    }

    location /vless {
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }

    location /vmess {
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }

    location /trojan {
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_pass http://127.0.0.1:10003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }
}
EOF

ln -sf /etc/nginx/sites-available/vpn /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# 6. SSL Certbot
echo -e "${YELLOW}[6/6] Obtaining SSL Certificate...${PLAIN}"
systemctl stop nginx
certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m admin@"$DOMAIN"

# Update Nginx to listen on 443 SSL
# We simply replace the listen 80 with ssl config
# Or we can let Certbot --nginx do it, but sometimes it fails with custom locations.
# Let's manually write the SSL config now that we have certs.

if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    cat > /etc/nginx/sites-available/vpn <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    root /var/www/vpanel;
    index index.html;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        auth_basic "VPN Admin Area";
        auth_basic_user_file /etc/nginx/.htpasswd;
        try_files \$uri \$uri/ /index.html;
    }

    location /vless {
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_pass http://127.0.0.1:10001;
        proxy_redirect off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /vmess {
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_pass http://127.0.0.1:10002;
        proxy_redirect off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /trojan {
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_pass http://127.0.0.1:10003;
        proxy_redirect off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
else
    echo -e "${RED}SSL Certificate failed! Nginx will run on port 80 (Insecure).${PLAIN}"
fi

systemctl restart nginx

echo -e "${GREEN}==========================================${PLAIN}"
echo -e "${GREEN}       VPN Installation Complete!         ${PLAIN}"
echo -e "${GREEN}==========================================${PLAIN}"
echo -e "Domain: https://$DOMAIN"
echo -e "UUID:   $UUID"
echo -e "Dashboard Login:"
echo -e "  User: admin"
echo -e "  Pass: $UUID"
echo -e "=========================================="
