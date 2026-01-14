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
apt update && apt install -y curl wget git nginx certbot python3-certbot-nginx unzip uuid-runtime apache2-utils qrencode php-fpm php-cli php-xml sudo

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
        "clients": [ { "id": "$UUID", "email": "admin" } ],
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
        "clients": [ { "id": "$UUID", "email": "admin" } ]
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
        "clients": [ { "password": "$UUID", "email": "admin" } ]
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

# Set Permissions for Xray Config (So PHP can write to it)
chown root:www-data /usr/local/etc/xray/config.json
chmod 664 /usr/local/etc/xray/config.json

# Restart Xray
systemctl restart xray
systemctl enable xray

# 5. Configure Nginx & Dashboard
echo -e "${YELLOW}[5/6] Setting up Nginx & Dashboard (PHP)...${PLAIN}"

# Dashboard Directory
mkdir -p /var/www/vpanel
rm -f /var/www/vpanel/index.html

# --- INITIAL USERS DB ---
# Initialize users.json with the admin/default account
echo "[{\"username\":\"admin\",\"uuid\":\"$UUID\",\"created_at\":\"$(date)\"}]" > /etc/vpanel_users.json
chown root:www-data /etc/vpanel_users.json
chmod 660 /etc/vpanel_users.json # RW for root and www-data

# --- SUDOERS FOR PHP ---
# Allow www-data to restart xray AND run update script without password
echo "www-data ALL=(root) NOPASSWD: /usr/bin/systemctl restart xray" > /etc/sudoers.d/vpanel
echo "www-data ALL=(root) NOPASSWD: /usr/local/bin/vpanel-update" >> /etc/sudoers.d/vpanel
chmod 0440 /etc/sudoers.d/vpanel

# --- INSTALL UPDATE SCRIPT ---
# We write a default update script that can be customized
cat > /usr/local/bin/vpanel-update <<'BASH'
#!/bin/bash
# VPanel Auto-Updater
# Replace with your repo URL
REPO_URL="https://raw.githubusercontent.com/USER/REPO/main/vps-installer/install.sh"

echo "Checking for updates..."
# Logic to fetch and extract PHP would go here.
# For now, we echo a placeholder message.
echo "Update feature is installed. Configure /usr/local/bin/vpanel-update with your GitHub URL."
BASH
chmod +x /usr/local/bin/vpanel-update

# --- LOGIN PAGE (PHP) ---
cat > /var/www/vpanel/login.php <<'PHP'
<?php
session_start();
$users_file = '/etc/vpanel_users.json';
$users = json_decode(file_get_contents($users_file), true);
$admin_uuid = $users[0]['uuid'] ?? '';

if(isset($_POST['password'])) {
    if($_POST['password'] === $admin_uuid) {
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
        body { margin: 0; padding: 0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #0f0c29; background: linear-gradient(to right, #24243e, #302b63, #0f0c29); height: 100vh; display: flex; justify-content: center; align-items: center; color: #fff; }
        .login-card { background: rgba(255, 255, 255, 0.05); backdrop-filter: blur(10px); padding: 40px; border-radius: 15px; box-shadow: 0 15px 25px rgba(0,0,0,0.6); width: 300px; text-align: center; border: 1px solid rgba(255, 215, 0, 0.2); }
        h2 { margin-bottom: 30px; color: #ffd700; text-transform: uppercase; letter-spacing: 2px; }
        input[type="password"] { width: 100%; padding: 10px 0; font-size: 16px; color: #fff; margin-bottom: 30px; border: none; border-bottom: 1px solid #fff; outline: none; background: transparent; }
        button { background: linear-gradient(45deg, #ffd700, #fdb931); border: none; padding: 10px 20px; cursor: pointer; border-radius: 5px; color: #000; font-weight: bold; width: 100%; transition: 0.3s; }
        button:hover { transform: scale(1.05); box-shadow: 0 0 15px #ffd700; }
        .error { color: #ff4444; font-size: 12px; margin-bottom: 15px; }
    </style>
</head>
<body>
    <div class="login-card">
        <h2>Admin Access</h2>
        <?php if(isset($error)) echo "<p class='error'>$error</p>"; ?>
        <form method="POST">
            <input type="password" name="password" placeholder="Enter Admin UUID" required>
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
if(!isset($_SESSION['logged_in'])) { header('Location: login.php'); exit; }

$domain = $_SERVER['HTTP_HOST'];
$users_file = '/etc/vpanel_users.json';
$xray_config = '/usr/local/etc/xray/config.json';

// Fetch ISP Info
$isp_info = "Loading..."; $loc_info = "Unknown";
try {
    $ctx = stream_context_create(['http'=> ['timeout' => 2]]);
    $json = @file_get_contents("http://ip-api.com/json/", false, $ctx);
    if($json) { $data = json_decode($json, true); $isp_info = $data['isp'] ?? "Unknown ISP"; $loc_info = ($data['city'] ?? "") . ", " . ($data['country'] ?? ""); }
} catch(Exception $e) {}

function getUsers() { global $users_file; return json_decode(file_get_contents($users_file), true); }
function saveUsers($users) { global $users_file; file_put_contents($users_file, json_encode($users, JSON_PRETTY_PRINT)); }
function updateXrayConfig($users) {
    global $xray_config;
    if(!is_writable($xray_config)) { return false; }
    $config = json_decode(file_get_contents($xray_config), true);
    $clients = []; $trojan_clients = [];
    foreach($users as $u) {
        $clients[] = ["id" => $u['uuid'], "email" => $u['username']];
        $trojan_clients[] = ["password" => $u['uuid'], "email" => $u['username']];
    }
    $config['inbounds'][0]['settings']['clients'] = $clients;
    $config['inbounds'][1]['settings']['clients'] = $clients;
    $config['inbounds'][2]['settings']['clients'] = $trojan_clients;
    file_put_contents($xray_config, json_encode($config, JSON_PRETTY_PRINT));
    shell_exec('sudo systemctl restart xray');
    return true;
}
function uuidv4() {
    $data = random_bytes(16);
    $data[6] = chr(ord($data[6]) & 0x0f | 0x40);
    $data[8] = chr(ord($data[8]) & 0x3f | 0x80);
    return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($data), 4));
}

// UPDATE LOGIC
$update_msg = "";
if(isset($_POST['action'])) {
    if($_POST['action'] === 'add') {
        $users = getUsers();
        $username = htmlspecialchars($_POST['username']);
        $uuid = uuidv4();
        $users[] = ["username" => $username, "uuid" => $uuid, "created_at" => date('Y-m-d H:i:s')];
        saveUsers($users); updateXrayConfig($users);
    }
    elseif($_POST['action'] === 'delete') {
        $users = getUsers();
        $uuid_to_del = $_POST['uuid'];
        $new_users = [];
        foreach($users as $u) { if($u['uuid'] !== $uuid_to_del) { $new_users[] = $u; } }
        saveUsers($new_users); updateXrayConfig($new_users);
    }
    elseif($_POST['action'] === 'update_web') {
        $output = shell_exec('sudo vpanel-update 2>&1');
        $update_msg = "Update Check: " . htmlspecialchars($output);
    }
}
$users = getUsers();

// Stats
$load = sys_getloadavg(); $cpu_load = $load[0] * 100;
$free = shell_exec('free -m'); $free_arr = explode("\n", trim($free));
$mem = array_merge(array_filter(explode(" ", $free_arr[1])));
$mem_percent = round(($mem[2] / $mem[1]) * 100);
$net = file_get_contents('/proc/net/dev');
preg_match('/(eth0|venet0|ens\d+):\s*(\d+)\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+(\d+)/', $net, $matches);
$rx = isset($matches[2]) ? round($matches[2]/1024/1024, 2) : 0;
$tx = isset($matches[3]) ? round($matches[3]/1024/1024, 2) : 0;
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPN Admin Panel</title>
    <script src="https://cdn.jsdelivr.net/npm/qrcode@1.4.4/build/qrcode.min.js"></script>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        :root { --gold: #ffd700; --dark: #1a1a2e; --card-bg: rgba(255,255,255,0.05); }
        body { font-family: 'Segoe UI', sans-serif; background: linear-gradient(135deg, #0f0c29, #302b63, #24243e); color: #e0e0e0; margin: 0; padding-bottom: 50px; }
        .header { background: rgba(0,0,0,0.3); padding: 20px; text-align: center; border-bottom: 1px solid rgba(255,215,0,0.1); }
        h1 { margin: 0; color: var(--gold); letter-spacing: 2px; }
        .container { max-width: 1000px; margin: 30px auto; padding: 0 20px; }
        .card { background: var(--card-bg); backdrop-filter: blur(10px); border-radius: 15px; padding: 20px; border: 1px solid rgba(255,255,255,0.1); margin-bottom: 20px; }
        .row { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; }
        .stat-val { font-size: 1.5rem; color: #fff; font-weight: bold; }

        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid rgba(255,255,255,0.1); }
        th { color: var(--gold); text-transform: uppercase; font-size: 0.9rem; }
        tr:hover { background: rgba(255,255,255,0.05); }

        input[type="text"] { background: rgba(0,0,0,0.3); border: 1px solid #444; padding: 10px; color: #fff; border-radius: 5px; width: 200px; }
        .btn { padding: 10px 20px; border: none; border-radius: 5px; cursor: pointer; font-weight: bold; }
        .btn-add { background: var(--gold); color: #000; }
        .btn-del { background: #ff4444; color: #fff; padding: 5px 10px; font-size: 0.8rem; }
        .btn-link { background: #007bff; color: #fff; padding: 5px 10px; font-size: 0.8rem; text-decoration: none; display: inline-block; border-radius: 3px; cursor: pointer; }
        .btn-update { background: transparent; border: 1px solid var(--gold); color: var(--gold); padding: 5px 15px; font-size: 0.8rem; }
        .btn-update:hover { background: var(--gold); color: #000; }

        @media (max-width: 768px) {
            .row { grid-template-columns: 1fr 1fr; }
            input[type="text"] { width: 100%; margin-bottom: 10px; }
            form { flex-direction: column; align-items: stretch; }
        }

        .modal { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); z-index: 1000; justify-content: center; align-items: center; }
        .modal-content { background: #222; padding: 30px; border-radius: 10px; text-align: center; max-width: 500px; width: 90%; }
        textarea { width: 100%; height: 100px; background: #111; color: #0f0; border: none; padding: 10px; margin-top: 10px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>VPS MANAGER</h1>
    </div>

    <div class="container">
        <!-- Update Message -->
        <?php if($update_msg): ?>
        <div style="background: rgba(0,255,0,0.2); padding: 10px; border-radius: 5px; margin-bottom: 20px; border: 1px solid #0f0; text-align: center;">
            <?php echo $update_msg; ?>
        </div>
        <?php endif; ?>

        <!-- Server Info Card -->
        <div class="card">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px;">
                <h3 style="color: var(--gold); margin: 0;">Server Information</h3>
                <form method="POST" style="margin:0;">
                    <input type="hidden" name="action" value="update_web">
                    <button type="submit" class="btn btn-update" title="Update Web Panel Script"><i class="fas fa-sync-alt"></i> Update Panel</button>
                </form>
            </div>

            <div style="display: flex; justify-content: space-between; flex-wrap: wrap;">
                <div>
                    <strong style="color: #aaa;">Domain:</strong> <span style="color: #fff;"><?php echo $domain; ?></span><br>
                    <strong style="color: #aaa;">ISP:</strong> <span style="color: #fff;"><?php echo $isp_info; ?></span>
                </div>
                <div style="text-align: right;">
                    <strong style="color: #aaa;">Location:</strong> <span style="color: #fff;"><?php echo $loc_info; ?></span><br>
                    <strong style="color: #aaa;">IP:</strong> <span style="color: #fff;"><?php echo $_SERVER['SERVER_ADDR']; ?></span>
                </div>
            </div>
        </div>

        <!-- Stats -->
        <div class="row">
            <div class="card">
                <h3>CPU Load</h3>
                <div class="stat-val"><?php echo round($cpu_load,1); ?>%</div>
            </div>
            <div class="card">
                <h3>RAM Usage</h3>
                <div class="stat-val"><?php echo $mem_percent; ?>%</div>
            </div>
            <div class="card">
                <h3>Total Traffic</h3>
                <div class="stat-val"><?php echo $rx + $tx; ?> MB</div>
            </div>
        </div>

        <!-- Add User -->
        <div class="card">
            <h3 style="color: var(--gold);">Create New User</h3>
            <form method="POST">
                <input type="hidden" name="action" value="add">
                <input type="text" name="username" placeholder="Username" required>
                <button type="submit" class="btn btn-add"><i class="fas fa-plus"></i> Generate Account</button>
            </form>
        </div>

        <!-- User List -->
        <div class="card">
            <h3 style="color: var(--gold);">User Management</h3>
            <div style="overflow-x: auto;">
                <table>
                    <thead>
                        <tr>
                            <th>Username</th>
                            <th>UUID</th>
                            <th>Created</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach($users as $u): ?>
                        <tr>
                            <td><?php echo htmlspecialchars($u['username']); ?></td>
                            <td style="font-family: monospace; font-size: 0.9rem;"><?php echo $u['uuid']; ?></td>
                            <td style="font-size: 0.8rem; color: #aaa;"><?php echo $u['created_at']; ?></td>
                            <td>
                                <button class="btn-link" onclick="showLinks('<?php echo $u['uuid']; ?>', '<?php echo $domain; ?>')">Links</button>
                                <?php if($u['username'] !== 'admin'): ?>
                                <form method="POST" style="display:inline;" onsubmit="return confirm('Delete user?');">
                                    <input type="hidden" name="action" value="delete">
                                    <input type="hidden" name="uuid" value="<?php echo $u['uuid']; ?>">
                                    <button type="submit" class="btn btn-del">Delete</button>
                                </form>
                                <?php endif; ?>
                            </td>
                        </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </div>
    </div>

    <!-- Modal -->
    <div id="linkModal" class="modal">
        <div class="modal-content">
            <h3 style="color: var(--gold);">Connection Config</h3>
            <div style="margin-bottom: 10px;">
                <button class="btn-link" onclick="setProto('vless')">VLESS</button>
                <button class="btn-link" onclick="setProto('vmess')">VMess</button>
                <button class="btn-link" onclick="setProto('trojan')">Trojan</button>
            </div>
            <div id="qrcode" style="display: flex; justify-content: center; background: white; padding: 10px; width: fit-content; margin: 10px auto;"></div>
            <textarea id="configText" readonly></textarea>
            <button class="btn btn-add" onclick="closeModal()" style="margin-top: 10px;">Close</button>
        </div>
    </div>

    <script>
        let currentUuid = '';
        let currentHost = '';
        let currentProto = 'vless';

        function showLinks(uuid, host) {
            currentUuid = uuid;
            currentHost = host;
            document.getElementById('linkModal').style.display = 'flex';
            setProto('vless');
        }

        function closeModal() {
            document.getElementById('linkModal').style.display = 'none';
        }

        function setProto(proto) {
            currentProto = proto;
            generate();
        }

        function generate() {
            const port = "443";
            const path = "/" + currentProto;
            let link = "";

            if (currentProto === "vless") {
                link = `vless://${currentUuid}@${currentHost}:${port}?path=${path}&security=tls&encryption=none&type=ws&host=${currentHost}&sni=${currentHost}#${currentHost}-VLESS`;
            } else if (currentProto === "trojan") {
                link = `trojan://${currentUuid}@${currentHost}:${port}?path=${path}&security=tls&type=ws&host=${currentHost}&sni=${currentHost}#${currentHost}-Trojan`;
            } else if (currentProto === "vmess") {
                const vmessJson = {
                    v: "2", ps: `${currentHost}-VMess`, add: currentHost, port: port, id: currentUuid, aid: "0",
                    scy: "auto", net: "ws", type: "none", host: currentHost, path: path, tls: "tls", sni: currentHost
                };
                link = "vmess://" + btoa(JSON.stringify(vmessJson));
            }

            document.getElementById('configText').value = link;
            document.getElementById('qrcode').innerHTML = "";
            QRCode.toCanvas(link, { width: 200, margin: 2 }, (err, canvas) => {
                if(!err) document.getElementById('qrcode').appendChild(canvas);
            });
        }
    </script>
</body>
</html>
PHP

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
echo -e "Pass: $UUID (Admin Key)"
echo -e "=========================================="
