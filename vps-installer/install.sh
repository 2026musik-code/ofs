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
apt update && apt install -y curl wget git nginx certbot python3-certbot-nginx unzip uuid-runtime apache2-utils qrencode php-fpm php-cli php-xml

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
  "stats": {},
  "api": {
    "services": [
      "StatsService"
    ],
    "tag": "api"
  },
  "policy": {
    "levels": {
      "0": {
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true
    }
  },
  "inbounds": [
    {
      "port": 10001,
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "$UUID", "email": "admin@vps" } ],
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
        "clients": [ { "id": "$UUID", "email": "admin@vps" } ]
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
        "clients": [ { "password": "$UUID", "email": "admin@vps" } ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/trojan" }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 10080,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "tag": "api"
    }
  ],
  "outbounds": [
    { "protocol": "freedom" },
    { "protocol": "blackhole", "tag": "block" }
  ],
  "routing": {
    "rules": [
      {
        "inboundTag": [
          "api"
        ],
        "outboundTag": "api",
        "type": "field"
      }
    ]
  }
}
EOF

# Restart Xray
systemctl restart xray
systemctl enable xray

# 5. Configure Nginx & Dashboard
echo -e "${YELLOW}[5/6] Setting up Nginx & Dashboard (PHP)...${PLAIN}"

# Dashboard Directory
mkdir -p /var/www/vpanel
rm -f /var/www/vpanel/index.html # Remove old HTML if exists

# --- LOGIN PAGE (PHP) ---
cat > /var/www/vpanel/login.php <<'PHP'
<?php
session_start();
if(isset($_POST['password'])) {
    $config_uuid = trim(file_get_contents('/etc/vpanel_uuid'));
    if($_POST['password'] === $config_uuid) {
        $_SESSION['logged_in'] = true;
        header('Location: index.php');
        exit;
    } else {
        $error = "Invalid Password";
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Premium Login</title>
    <style>
        body {
            margin: 0;
            padding: 0;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #0f0c29;  /* fallback for old browsers */
            background: linear-gradient(to right, #24243e, #302b63, #0f0c29);
            height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            color: #fff;
        }
        .login-card {
            background: rgba(255, 255, 255, 0.05);
            backdrop-filter: blur(10px);
            padding: 40px;
            border-radius: 15px;
            box-shadow: 0 15px 25px rgba(0,0,0,0.6);
            width: 300px;
            text-align: center;
            border: 1px solid rgba(255, 215, 0, 0.2);
        }
        h2 { margin-bottom: 30px; color: #ffd700; text-transform: uppercase; letter-spacing: 2px; }
        input[type="password"] {
            width: 100%;
            padding: 10px 0;
            font-size: 16px;
            color: #fff;
            margin-bottom: 30px;
            border: none;
            border-bottom: 1px solid #fff;
            outline: none;
            background: transparent;
        }
        button {
            background: linear-gradient(45deg, #ffd700, #fdb931);
            border: none;
            padding: 10px 20px;
            cursor: pointer;
            border-radius: 5px;
            color: #000;
            font-weight: bold;
            width: 100%;
            transition: 0.3s;
        }
        button:hover { transform: scale(1.05); box-shadow: 0 0 15px #ffd700; }
        .error { color: #ff4444; font-size: 12px; margin-bottom: 15px; }
    </style>
</head>
<body>
    <div class="login-card">
        <h2>Admin Access</h2>
        <?php if(isset($error)) echo "<p class='error'>$error</p>"; ?>
        <form method="POST">
            <input type="password" name="password" placeholder="Enter UUID Key" required>
            <button type="submit">LOGIN</button>
        </form>
    </div>
</body>
</html>
PHP

# --- DASHBOARD (PHP) ---
cat > /var/www/vpanel/index.php <<'PHP'
<?php
session_start();
if(!isset($_SESSION['logged_in'])) {
    header('Location: login.php');
    exit;
}

$domain = $_SERVER['HTTP_HOST'];
$uuid = trim(file_get_contents('/etc/vpanel_uuid'));

// --- Server Stats ---
// CPU Load
$load = sys_getloadavg();
$cpu_load = $load[0] * 100; // Rough estimate percentage based on 1 core

// RAM Usage
$free = shell_exec('free -m');
$free = (string)trim($free);
$free_arr = explode("\n", $free);
$mem = explode(" ", $free_arr[1]);
$mem = array_filter($mem);
$mem = array_merge($mem);
$mem_total = $mem[1];
$mem_used = $mem[2];
$mem_percent = round(($mem_used / $mem_total) * 100);

// Traffic (Interface eth0 or venet0)
$net = file_get_contents('/proc/net/dev');
preg_match('/(eth0|venet0|ens\d+):\s*(\d+)\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+(\d+)/', $net, $matches);
$rx_total = isset($matches[2]) ? round($matches[2] / 1024 / 1024, 2) : 0; // MB
$tx_total = isset($matches[3]) ? round($matches[3] / 1024 / 1024, 2) : 0; // MB
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Premium VPN Panel</title>
    <script src="https://cdn.jsdelivr.net/npm/qrcode@1.4.4/build/qrcode.min.js"></script>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        :root { --gold: #ffd700; --dark: #1a1a2e; --light: #e0e0e0; --card-bg: rgba(255,255,255,0.05); }
        body {
            font-family: 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #0f0c29, #302b63, #24243e);
            color: var(--light);
            margin: 0;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
        }
        .header {
            width: 100%;
            padding: 20px;
            background: rgba(0,0,0,0.3);
            text-align: center;
            border-bottom: 1px solid rgba(255, 215, 0, 0.1);
        }
        .header h1 { margin: 0; color: var(--gold); letter-spacing: 2px; }

        .container {
            max-width: 1000px;
            width: 95%;
            margin-top: 30px;
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
        }

        .card {
            background: var(--card-bg);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            padding: 20px;
            border: 1px solid rgba(255,255,255,0.1);
            transition: transform 0.3s;
        }
        .card:hover { transform: translateY(-5px); border-color: var(--gold); }

        .stat-box { display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px; }
        .stat-title { font-size: 0.9rem; color: #aaa; }
        .stat-value { font-size: 1.5rem; font-weight: bold; color: #fff; }
        .progress-bar { width: 100%; height: 6px; background: #333; border-radius: 3px; overflow: hidden; }
        .progress-fill { height: 100%; background: var(--gold); width: 0%; transition: width 1s; }

        .tabs { display: flex; gap: 10px; margin-bottom: 20px; justify-content: center; }
        .tab-btn {
            background: transparent;
            border: 1px solid var(--gold);
            color: var(--gold);
            padding: 8px 20px;
            border-radius: 20px;
            cursor: pointer;
            transition: 0.3s;
        }
        .tab-btn.active, .tab-btn:hover { background: var(--gold); color: #000; }

        textarea {
            width: 100%;
            height: 80px;
            background: rgba(0,0,0,0.3);
            border: 1px solid #444;
            color: #0f0;
            padding: 10px;
            border-radius: 5px;
            font-family: monospace;
            resize: none;
        }

        .copy-btn {
            width: 100%;
            margin-top: 10px;
            padding: 10px;
            background: var(--gold);
            border: none;
            color: #000;
            font-weight: bold;
            cursor: pointer;
            border-radius: 5px;
        }

        #qrcode { display: flex; justify-content: center; margin-top: 15px; padding: 10px; background: #fff; border-radius: 10px; width: fit-content; margin-left: auto; margin-right: auto; }

        .info-row { margin-bottom: 10px; font-size: 0.9rem; border-bottom: 1px solid rgba(255,255,255,0.05); padding-bottom: 5px; }
        .info-label { color: #aaa; }
        .info-val { float: right; color: #fff; }
    </style>
</head>
<body>
    <div class="header">
        <h1><i class="fas fa-shield-alt"></i> VPS CONTROL PANEL</h1>
    </div>

    <div class="container">
        <!-- System Stats -->
        <div class="card">
            <h3 style="color: var(--gold); margin-top: 0;"><i class="fas fa-server"></i> Server Status</h3>

            <div class="stat-box">
                <div>
                    <div class="stat-title">CPU Load</div>
                    <div class="stat-value"><?php echo round($cpu_load, 1); ?>%</div>
                </div>
                <i class="fas fa-microchip fa-2x" style="color: #555;"></i>
            </div>
            <div class="progress-bar"><div class="progress-fill" style="width: <?php echo min($cpu_load, 100); ?>%"></div></div>
            <br>

            <div class="stat-box">
                <div>
                    <div class="stat-title">RAM Usage</div>
                    <div class="stat-value"><?php echo $mem_percent; ?>%</div>
                    <small style="color:#666;"><?php echo $mem_used . "MB / " . $mem_total . "MB"; ?></small>
                </div>
                <i class="fas fa-memory fa-2x" style="color: #555;"></i>
            </div>
            <div class="progress-bar"><div class="progress-fill" style="width: <?php echo $mem_percent; ?>%"></div></div>
        </div>

        <!-- Network Stats -->
        <div class="card">
            <h3 style="color: var(--gold); margin-top: 0;"><i class="fas fa-network-wired"></i> Network Traffic</h3>
            <div class="info-row">
                <span class="info-label">Domain</span>
                <span class="info-val"><?php echo $domain; ?></span>
            </div>
            <div class="info-row">
                <span class="info-label">Total Download (RX)</span>
                <span class="info-val"><?php echo $rx_total; ?> MB</span>
            </div>
            <div class="info-row">
                <span class="info-label">Total Upload (TX)</span>
                <span class="info-val"><?php echo $tx_total; ?> MB</span>
            </div>
             <div class="info-row">
                <span class="info-label">Account Type</span>
                <span class="info-val">Single User (Admin)</span>
            </div>
            <div class="info-row">
                <span class="info-label">Traffic Usage</span>
                <span class="info-val">See Total Network Above</span>
            </div>
        </div>

        <!-- Config Generator -->
        <div class="card" style="grid-column: 1 / -1;">
            <div class="tabs">
                <button class="tab-btn active" onclick="setProto('vless')">VLESS</button>
                <button class="tab-btn" onclick="setProto('vmess')">VMess</button>
                <button class="tab-btn" onclick="setProto('trojan')">Trojan</button>
            </div>

            <textarea id="link" readonly></textarea>
            <button class="copy-btn" onclick="copyLink()">COPY CONFIGURATION</button>
            <div id="qrcode"></div>
        </div>
    </div>

    <script>
        const uuid = "<?php echo $uuid; ?>";
        const host = "<?php echo $domain; ?>";
        const port = "443";
        let currentProto = "vless";

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
                link = `vless://${uuid}@${host}:${port}?path=${path}&security=tls&encryption=none&type=ws&host=${host}&sni=${host}#${host}-VLESS`;
            } else if (currentProto === "trojan") {
                link = `trojan://${uuid}@${host}:${port}?path=${path}&security=tls&type=ws&host=${host}&sni=${host}#${host}-Trojan`;
            } else if (currentProto === "vmess") {
                const vmessJson = {
                    v: "2", ps: `${host}-VMess`, add: host, port: port, id: uuid, aid: "0",
                    scy: "auto", net: "ws", type: "none", host: host, path: path, tls: "tls", sni: host
                };
                link = "vmess://" + btoa(JSON.stringify(vmessJson));
            }

            document.getElementById('link').value = link;
            document.getElementById('qrcode').innerHTML = "";
            QRCode.toCanvas(link, { width: 200, margin: 2 }, (err, canvas) => {
                if(!err) document.getElementById('qrcode').appendChild(canvas);
            });
        }

        generate();

        function copyLink() {
            const el = document.getElementById('link');
            el.select();
            document.execCommand('copy');
            alert("Copied to clipboard!");
        }
    </script>
</body>
</html>
PHP

# Save UUID for PHP to read and secure it
echo "$UUID" > /etc/vpanel_uuid
chown root:www-data /etc/vpanel_uuid
chmod 640 /etc/vpanel_uuid

# 6. Configure Nginx to Handle PHP
echo -e "${YELLOW}[6/6] Configuring Nginx for PHP...${PLAIN}"

# Get PHP Version for FPM socket (e.g., php7.4-fpm.sock or php8.1-fpm.sock)
PHP_VER=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
PHP_SOCK="/run/php/php${PHP_VER}-fpm.sock"

# Nginx Config with PHP Support
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
    index index.php index.html;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # PHP Handler
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_SOCK;
    }

    # Disable Basic Auth since we use PHP Login
    location / {
        try_files \$uri \$uri/ /index.php;
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

# ENABLE NGINX CONFIG
ln -sf /etc/nginx/sites-available/vpn /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# SSL Certbot (Run only if certs don't exist)
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    echo -e "${YELLOW}Obtaining SSL...${PLAIN}"
    systemctl stop nginx
    certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m admin@"$DOMAIN"
    systemctl start nginx
else
    systemctl restart nginx
fi

echo -e "${GREEN}==========================================${PLAIN}"
echo -e "${GREEN}       PREMIUM VPN PANEL INSTALLED!       ${PLAIN}"
echo -e "${GREEN}==========================================${PLAIN}"
echo -e "URL:  https://$DOMAIN"
echo -e "Pass: $UUID"
echo -e "=========================================="
