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

echo -e "${GREEN}Starting VPS VPN Auto-Installer V2.1 (Secure Token System)...${PLAIN}"

# 1. System Update & Dependencies
echo -e "${YELLOW}[1/6] Updating System & Installing Dependencies...${PLAIN}"
apt update && apt install -y curl wget git nginx certbot python3-certbot-nginx unzip uuid-runtime apache2-utils qrencode php-fpm php-cli php-xml sudo cron jq

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

# Set Permissions for Xray Config
chown root:www-data /usr/local/etc/xray/config.json
chmod 664 /usr/local/etc/xray/config.json

# Restart Xray
systemctl restart xray
systemctl enable xray

# 5. Configure Nginx & Dashboard V2
echo -e "${YELLOW}[5/6] Setting up Nginx & Dashboard V2 (PHP)...${PLAIN}"

# Dashboard Directory
mkdir -p /var/www/vpanel
rm -f /var/www/vpanel/index.html

# --- INITIAL DATABASES ---
echo "[{\"username\":\"admin\",\"uuid\":\"$UUID\",\"created_at\":\"$(date)\",\"exp_date\":\"9999-12-31\",\"owner_id\":\"000000\"}]" > /etc/vpanel_users.json
chown root:www-data /etc/vpanel_users.json
chmod 660 /etc/vpanel_users.json

echo "[]" > /etc/vpanel_tokens.json
chown root:www-data /etc/vpanel_tokens.json
chmod 660 /etc/vpanel_tokens.json

echo "$UUID" > /etc/vpanel_uuid
chown root:www-data /etc/vpanel_uuid
chmod 640 /etc/vpanel_uuid

# --- SUDOERS ---
echo "www-data ALL=(root) NOPASSWD: /usr/bin/systemctl restart xray" > /etc/sudoers.d/vpanel
echo "www-data ALL=(root) NOPASSWD: /usr/local/bin/vpanel-update" >> /etc/sudoers.d/vpanel
chmod 0440 /etc/sudoers.d/vpanel

# --- UPDATE SCRIPT ---
cat > /usr/local/bin/vpanel-update <<'BASH'
#!/bin/bash
# VPanel Auto-Updater
REPO_URL="https://raw.githubusercontent.com/2026musik-code/ofs/main/vps-installer/install2.sh"
TEMP_FILE="/tmp/vpanel_install_update.sh"

echo "Checking for updates..."
if curl -s -f -o "$TEMP_FILE" "$REPO_URL"; then
    echo "Download success."
    # Extract PHP files from install2.sh
    sed -n "/cat > \/var\/www\/vpanel\/index.php <<'PHP'/,/^PHP$/p" "$TEMP_FILE" | sed '1d;$d' > /var/www/vpanel/index.php
    sed -n "/cat > \/var\/www\/vpanel\/admin.php <<'PHP'/,/^PHP$/p" "$TEMP_FILE" | sed '1d;$d' > /var/www/vpanel/admin.php
    sed -n "/cat > \/var\/www\/vpanel\/admin_login.php <<'PHP'/,/^PHP$/p" "$TEMP_FILE" | sed '1d;$d' > /var/www/vpanel/admin_login.php
    echo "Dashboard updated successfully!"
    rm -f "$TEMP_FILE"
else
    echo "Error: Failed to download update script."
    exit 1
fi
BASH
chmod +x /usr/local/bin/vpanel-update

# --- EXPIRED CHECKER ---
cat > /usr/local/bin/vpanel-check-expired.php <<'PHP'
<?php
$users_file = '/etc/vpanel_users.json';
$xray_config = '/usr/local/etc/xray/config.json';
if(!file_exists($users_file)) exit;
$users = json_decode(file_get_contents($users_file), true);
$today = date('Y-m-d');
$changed = false;
$new_users = [];
foreach($users as $u) {
    if($u['username'] === 'admin') { $new_users[] = $u; continue; }
    if(isset($u['exp_date']) && $u['exp_date'] < $today) { $changed = true; }
    else { $new_users[] = $u; }
}
if($changed) {
    file_put_contents($users_file, json_encode($new_users, JSON_PRETTY_PRINT));
    $config = json_decode(file_get_contents($xray_config), true);
    $clients = []; $trojan_clients = [];
    foreach($new_users as $u) {
        $clients[] = ["id" => $u['uuid'], "email" => $u['username']];
        $trojan_clients[] = ["password" => $u['uuid'], "email" => $u['username']];
    }
    $config['inbounds'][0]['settings']['clients'] = $clients;
    $config['inbounds'][1]['settings']['clients'] = $clients;
    $config['inbounds'][2]['settings']['clients'] = $trojan_clients;
    file_put_contents($xray_config, json_encode($config, JSON_PRETTY_PRINT));
    shell_exec('sudo systemctl restart xray');
}
?>
PHP
chmod +x /usr/local/bin/vpanel-check-expired.php
(crontab -l 2>/dev/null; echo "0 0 * * * /usr/bin/php /usr/local/bin/vpanel-check-expired.php") | crontab -

# ==========================================
#        DASHBOARD V2 PHP FILES
# ==========================================

# --- 1. ADMIN LOGIN ---
cat > /var/www/vpanel/admin_login.php <<'PHP'
<?php
session_start();
$admin_pass = trim(file_get_contents('/etc/vpanel_uuid'));
if(isset($_POST['password'])) {
    if($_POST['password'] === $admin_pass) {
        $_SESSION['admin_logged_in'] = true;
        header('Location: admin.php'); exit;
    } else { $error = "Invalid Password"; }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Admin Login</title>
    <style>
        body { margin: 0; font-family: 'Segoe UI', sans-serif; background: linear-gradient(135deg, #0f0c29, #302b63, #24243e); height: 100vh; display: flex; justify-content: center; align-items: center; color: #fff; }
        .card { background: rgba(255,255,255,0.05); backdrop-filter: blur(10px); padding: 30px; border-radius: 15px; width: 300px; text-align: center; border: 1px solid rgba(255,215,0,0.2); }
        input { width: 90%; padding: 10px; margin-bottom: 20px; background: rgba(0,0,0,0.3); border: 1px solid #555; color: #fff; border-radius: 5px; }
        button { width: 100%; padding: 10px; background: #ffd700; border: none; font-weight: bold; cursor: pointer; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="card">
        <h2 style="color: #ffd700;">OWNER PANEL</h2>
        <?php if(isset($error)) echo "<p style='color:red; font-size:0.8rem;'>$error</p>"; ?>
        <form method="POST">
            <input type="password" name="password" placeholder="Admin UUID" required>
            <button type="submit">LOGIN</button>
        </form>
        <br>
        <a href="index.php" style="color: #aaa; font-size: 0.8rem;">Back to Public</a>
    </div>
</body>
</html>
PHP

# --- 2. ADMIN DASHBOARD ---
cat > /var/www/vpanel/admin.php <<'PHP'
<?php
session_start();
if(!isset($_SESSION['admin_logged_in'])) { header('Location: admin_login.php'); exit; }

$users_file = '/etc/vpanel_users.json';
$tokens_file = '/etc/vpanel_tokens.json';
$xray_config = '/usr/local/etc/xray/config.json';

function getUsers() { global $users_file; return json_decode(file_get_contents($users_file), true); }
function getTokens() { global $tokens_file; return json_decode(file_get_contents($tokens_file), true); }
function saveUsers($data) { global $users_file; file_put_contents($users_file, json_encode($data, JSON_PRETTY_PRINT)); }
function saveTokens($data) { global $tokens_file; file_put_contents($tokens_file, json_encode($data, JSON_PRETTY_PRINT)); }

function updateXrayConfig($users) {
    global $xray_config; if(!is_writable($xray_config)) return;
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
}

$update_msg = "";
if(isset($_POST['action'])) {
    if($_POST['action'] === 'generate_token') {
        $tokens = getTokens();
        $token_str = "VPN-" . strtoupper(substr(bin2hex(random_bytes(3)), 0, 5));
        $pin = rand(100000, 999999);
        $tokens[] = ["token" => $token_str, "owner_id" => $pin, "created_at" => date('Y-m-d H:i')];
        saveTokens($tokens);
        header("Location: admin.php"); exit;
    }
    elseif($_POST['action'] === 'delete_user') {
        $users = getUsers();
        $uuid_del = $_POST['uuid'];
        $new_users = [];
        foreach($users as $u) { if($u['uuid'] !== $uuid_del) $new_users[] = $u; }
        saveUsers($new_users); updateXrayConfig($new_users);
        header("Location: admin.php"); exit;
    }
    elseif($_POST['action'] === 'delete_token') {
        $tokens = getTokens();
        $tok_del = $_POST['token'];
        $new_tokens = [];
        foreach($tokens as $t) { if($t['token'] !== $tok_del) $new_tokens[] = $t; }
        saveTokens($new_tokens);
        header("Location: admin.php"); exit;
    }
    elseif($_POST['action'] === 'update_web') {
        $output = shell_exec('sudo vpanel-update 2>&1');
        $update_msg = "Update: " . htmlspecialchars($output);
    }
    elseif($_POST['action'] === 'logout') {
        session_destroy();
        header("Location: admin_login.php"); exit;
    }
}

$users = getUsers();
$tokens = getTokens();

// --- SERVER STATS ---
$uptime = shell_exec("uptime -p");
$cpu_load = sys_getloadavg();
$ram_total = shell_exec("grep MemTotal /proc/meminfo | awk '{print $2}'");
$ram_free = shell_exec("grep MemAvailable /proc/meminfo | awk '{print $2}'");
$ram_used = $ram_total - $ram_free;
$ram_usage = round(($ram_used / $ram_total) * 100, 2);
$ip_info = json_decode(file_get_contents("http://ip-api.com/json/"), true);
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <title>Admin Panel</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        body { font-family: 'Segoe UI', sans-serif; background: #121212; color: #e0e0e0; margin: 0; padding: 15px; }
        .container { max-width: 900px; margin: 0 auto; padding-bottom: 60px; }
        .header-bar { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; border-bottom: 1px solid #333; padding-bottom: 15px; }
        h1 { color: #ffd700; margin: 0; font-size: 1.5rem; }

        .card { background: #1e1e1e; padding: 20px; border-radius: 12px; margin-bottom: 20px; border: 1px solid #333; box-shadow: 0 4px 10px rgba(0,0,0,0.2); }
        .card h2 { color: #ffd700; margin-top: 0; font-size: 1.2rem; border-bottom: 1px solid #333; padding-bottom: 10px; margin-bottom: 15px; display: flex; align-items: center; gap: 10px; }

        /* Stats Grid */
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 15px; }
        .stat-item { background: #252525; padding: 15px; border-radius: 8px; text-align: center; }
        .stat-val { display: block; font-size: 1.1rem; font-weight: bold; color: #fff; margin-top: 5px; }
        .stat-label { font-size: 0.85rem; color: #888; }

        /* Tables */
        .table-responsive { overflow-x: auto; border-radius: 8px; border: 1px solid #333; }
        table { width: 100%; border-collapse: collapse; min-width: 600px; }
        th, td { padding: 12px 15px; text-align: left; border-bottom: 1px solid #333; font-size: 0.9rem; }
        th { background: #252525; color: #ffd700; font-weight: 600; white-space: nowrap; }
        tr:last-child td { border-bottom: none; }
        tr:hover td { background: #252525; }

        /* Buttons */
        button { border: none; border-radius: 6px; cursor: pointer; font-weight: 600; transition: 0.2s; padding: 8px 12px; }
        .btn-sm { padding: 6px 10px; font-size: 0.85rem; }
        .btn-green { background: #28a745; color: white; width: 100%; padding: 12px; font-size: 1rem; }
        .btn-green:hover { background: #218838; }
        .btn-red { background: #dc3545; color: white; }
        .btn-red:hover { background: #c82333; }
        .btn-blue { background: #007bff; color: white; }
        .btn-logout { background: #444; color: #ccc; padding: 8px 15px; }
        .btn-logout:hover { background: #555; color: #fff; }

        .token-text { font-family: monospace; color: #0f0; letter-spacing: 1px; font-size: 1rem; }
        .pin-text { font-family: monospace; color: #ffd700; font-weight: bold; font-size: 1rem; }

        .nav-link { display: inline-block; margin-top: 20px; color: #aaa; text-decoration: none; border-bottom: 1px solid transparent; transition: 0.2s; }
        .nav-link:hover { color: #fff; border-bottom-color: #fff; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header-bar">
            <h1>OWNER DASHBOARD</h1>
            <form method="POST" style="margin:0;">
                <input type="hidden" name="action" value="logout">
                <button class="btn-logout"><i class="fas fa-sign-out-alt"></i> Logout</button>
            </form>
        </div>

        <?php if($update_msg) echo "<div style='background:#007bff;color:white;padding:15px;border-radius:8px;margin-bottom:20px;'>$update_msg</div>"; ?>

        <!-- Server Status -->
        <div class="card">
            <h2><i class="fas fa-server"></i> Server Status</h2>
            <div class="stats-grid">
                <div class="stat-item">
                    <span class="stat-label">IP Address</span>
                    <span class="stat-val"><?php echo $ip_info['query'] ?? 'Unknown'; ?></span>
                </div>
                <div class="stat-item">
                    <span class="stat-label">ISP / Location</span>
                    <span class="stat-val"><?php echo ($ip_info['isp']??'-') . " / " . ($ip_info['countryCode']??'-'); ?></span>
                </div>
                <div class="stat-item">
                    <span class="stat-label">Uptime</span>
                    <span class="stat-val"><?php echo $uptime; ?></span>
                </div>
                <div class="stat-item">
                    <span class="stat-label">CPU Load</span>
                    <span class="stat-val"><?php echo $cpu_load[0]; ?></span>
                </div>
                <div class="stat-item">
                    <span class="stat-label">RAM Usage</span>
                    <span class="stat-val"><?php echo $ram_usage; ?>%</span>
                    <span class="stat-label" style="font-size:0.7rem;"><?php echo round($ram_used/1024)." / ".round($ram_total/1024)." MB"; ?></span>
                </div>
            </div>
            <div style="margin-top: 15px; text-align: center;">
                 <form method="POST" style="margin:0;">
                    <input type="hidden" name="action" value="update_web">
                    <button type="submit" class="btn-blue btn-sm"><i class="fas fa-sync"></i> Update Web Panel</button>
                </form>
            </div>
        </div>

        <!-- Token Manager -->
        <div class="card">
            <h2><i class="fas fa-key"></i> Generate Token</h2>
            <p style="color:#aaa; font-size:0.9rem; margin-bottom: 15px;">Create a token for a user. They will need the <b>Token</b> to create an account and the <b>PIN</b> to view their config.</p>

            <form method="POST">
                <input type="hidden" name="action" value="generate_token">
                <button class="btn-green"><i class="fas fa-plus-circle"></i> GENERATE NEW TOKEN</button>
            </form>

            <h3 style="color:#eee; margin-top:25px; border-bottom:1px solid #333; padding-bottom:5px;">Active Tokens</h3>
            <div class="table-responsive">
                <table>
                    <thead>
                        <tr>
                            <th>Token</th>
                            <th>PIN (Owner ID)</th>
                            <th>Created</th>
                            <th style="text-align:center;">Action</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php if(empty($tokens)): ?>
                            <tr><td colspan="4" style="text-align:center; color:#666;">No active tokens.</td></tr>
                        <?php else: ?>
                            <?php foreach($tokens as $t): ?>
                            <tr>
                                <td class="token-text"><?php echo $t['token']; ?></td>
                                <td class="pin-text"><?php echo $t['owner_id']; ?></td>
                                <td><?php echo $t['created_at']; ?></td>
                                <td style="text-align:center;">
                                    <form method="POST" style="margin:0;" onsubmit="return confirm('Delete this token?');">
                                        <input type="hidden" name="action" value="delete_token">
                                        <input type="hidden" name="token" value="<?php echo $t['token']; ?>">
                                        <button class="btn-red btn-sm"><i class="fas fa-trash"></i></button>
                                    </form>
                                </td>
                            </tr>
                            <?php endforeach; ?>
                        <?php endif; ?>
                    </tbody>
                </table>
            </div>
        </div>

        <!-- User Manager -->
        <div class="card">
            <h2><i class="fas fa-users"></i> Manage Users</h2>
            <div class="table-responsive">
                <table>
                    <thead>
                        <tr>
                            <th>Username</th>
                            <th>PIN</th>
                            <th>Expiry</th>
                            <th style="text-align:center;">Action</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php
                        $user_count = 0;
                        foreach($users as $u):
                            if($u['username'] == 'admin') continue;
                            $user_count++;
                        ?>
                        <tr>
                            <td style="font-weight:bold;"><?php echo $u['username']; ?></td>
                            <td><?php echo $u['owner_id'] ?? '-'; ?></td>
                            <td><?php echo $u['exp_date']; ?></td>
                            <td style="text-align:center;">
                                <form method="POST" style="margin:0;" onsubmit="return confirm('Delete user <?php echo $u['username']; ?>?');">
                                    <input type="hidden" name="action" value="delete_user">
                                    <input type="hidden" name="uuid" value="<?php echo $u['uuid']; ?>">
                                    <button class="btn-red btn-sm"><i class="fas fa-trash"></i></button>
                                </form>
                            </td>
                        </tr>
                        <?php endforeach; ?>
                        <?php if($user_count == 0): ?>
                             <tr><td colspan="4" style="text-align:center; color:#666;">No active users.</td></tr>
                        <?php endif; ?>
                    </tbody>
                </table>
            </div>
        </div>

        <div style="text-align:center;">
            <a href="index.php" class="nav-link"><i class="fas fa-arrow-left"></i> Back to Public Dashboard</a>
        </div>
    </div>
</body>
</html>
PHP

# --- 3. PUBLIC DASHBOARD (INDEX - SECURE) ---
cat > /var/www/vpanel/index.php <<'PHP'
<?php
$domain = $_SERVER['HTTP_HOST'];
$users_file = '/etc/vpanel_users.json';
$tokens_file = '/etc/vpanel_tokens.json';
$xray_config = '/usr/local/etc/xray/config.json';

// --- HELPERS ---
function getUsers() { global $users_file; return json_decode(file_get_contents($users_file), true); }
function getTokens() { global $tokens_file; return json_decode(file_get_contents($tokens_file), true); }
function saveUsers($d) { global $users_file; file_put_contents($users_file, json_encode($d, JSON_PRETTY_PRINT)); }
function saveTokens($d) { global $tokens_file; file_put_contents($tokens_file, json_encode($d, JSON_PRETTY_PRINT)); }
function updateXrayConfig($users) {
    global $xray_config; if(!is_writable($xray_config)) return;
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
}
function uuidv4() {
    $data = random_bytes(16);
    $data[6] = chr(ord($data[6]) & 0x0f | 0x40);
    $data[8] = chr(ord($data[8]) & 0x3f | 0x80);
    return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($data), 4));
}

// --- LOGIC ---
$error = "";
// FETCH CONFIG (AJAX)
if(isset($_POST['action']) && $_POST['action'] === 'get_config') {
    $target_user = $_POST['username'];
    $input_pin = $_POST['pin'];
    $users = getUsers();
    $found = false;
    foreach($users as $u) {
        if($u['username'] === $target_user) {
            // Verify PIN securely on server
            if(isset($u['owner_id']) && (string)$u['owner_id'] === (string)$input_pin) {
                echo json_encode(["status" => "ok", "uuid" => $u['uuid'], "host" => $domain]);
                exit;
            }
        }
    }
    echo json_encode(["status" => "error", "message" => "Invalid PIN"]);
    exit;
}

// CREATE ACCOUNT
if(isset($_POST['action']) && $_POST['action'] === 'create_account') {
    $token_input = trim($_POST['token']);
    $username = htmlspecialchars(trim($_POST['username']));
    $days = (int)$_POST['days'];

    $tokens = getTokens();
    $valid_token = null;
    $token_idx = -1;

    foreach($tokens as $k => $t) {
        if($t['token'] === $token_input) {
            $valid_token = $t;
            $token_idx = $k;
            break;
        }
    }

    if($valid_token) {
        $users = getUsers();
        $uuid = uuidv4();
        $exp_date = date('Y-m-d', strtotime("+$days days"));
        $users[] = [
            "username" => $username,
            "uuid" => $uuid,
            "created_at" => date('Y-m-d H:i'),
            "exp_date" => $exp_date,
            "owner_id" => $valid_token['owner_id']
        ];
        array_splice($tokens, $token_idx, 1);
        saveUsers($users); saveTokens($tokens); updateXrayConfig($users);
        header("Location: index.php"); exit;
    } else {
        $error = "Token Invalid or Expired!";
    }
}

$users = getUsers();

// --- STATS ---
$uptime = shell_exec("uptime -p");
$cpu_load = sys_getloadavg();
$ram_total = shell_exec("grep MemTotal /proc/meminfo | awk '{print $2}'");
$ram_free = shell_exec("grep MemAvailable /proc/meminfo | awk '{print $2}'");
$ram_used = $ram_total - $ram_free;
$ram_usage = round(($ram_used / $ram_total) * 100, 2);
$ip_info = json_decode(file_get_contents("http://ip-api.com/json/"), true);
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <title>VPN Dashboard</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <script src="https://cdn.jsdelivr.net/npm/qrcode@1.4.4/build/qrcode.min.js"></script>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        :root { --gold: #ffd700; --dark: #121212; --card: #1e1e1e; }
        body { font-family: 'Segoe UI', sans-serif; background: #000; color: #fff; margin: 0; padding-bottom: 60px; }
        .header { text-align: center; padding: 20px; background: linear-gradient(to right, #111, #222); border-bottom: 2px solid var(--gold); }
        .container { max-width: 800px; margin: 20px auto; padding: 0 20px; }
        .card { background: var(--card); border-radius: 10px; padding: 20px; margin-bottom: 20px; border: 1px solid #333; }
        h1, h3 { color: var(--gold); margin-top: 0; }
        input, select { width: 100%; padding: 12px; margin-bottom: 10px; background: #333; border: 1px solid #555; color: #fff; border-radius: 5px; box-sizing: border-box; }
        button { width: 100%; padding: 12px; background: var(--gold); border: none; font-weight: bold; color: #000; border-radius: 5px; cursor: pointer; }
        table { width: 100%; border-collapse: collapse; }
        td { padding: 12px; border-bottom: 1px solid #333; }
        .status-active { color: #0f0; font-size: 0.8rem; border: 1px solid #0f0; padding: 2px 5px; border-radius: 4px; }
        .contact-btn { display: inline-block; width: 48%; text-align: center; padding: 10px; border-radius: 5px; text-decoration: none; color: white; font-weight: bold; margin-top: 10px; }
        .wa { background: #25D366; } .tg { background: #0088cc; }
        .modal { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.9); z-index: 999; justify-content: center; align-items: center; }
        .modal-content { background: #222; padding: 20px; width: 90%; max-width: 400px; border-radius: 10px; text-align: center; border: 1px solid var(--gold); }
    </style>
</head>
<body>
    <div class="header">
        <h1>VPN PUBLIC DASHBOARD</h1>
        <a href="admin_login.php" style="color: #666; text-decoration: none; font-size: 0.8rem;">[ Admin Login ]</a>
    </div>

    <div class="container">
        <!-- Stats -->
        <div class="card">
            <h3><i class="fas fa-server"></i> Server Status</h3>
            <div style="display: flex; flex-wrap: wrap; gap: 10px;">
                <div style="flex: 1; min-width: 150px; background: #222; padding: 10px; border-radius: 5px;">
                    <span style="color: #888;">ISP</span><br>
                    <strong><?php echo $ip_info['isp'] ?? '-'; ?></strong>
                </div>
                <div style="flex: 1; min-width: 150px; background: #222; padding: 10px; border-radius: 5px;">
                    <span style="color: #888;">CPU Load</span><br>
                    <strong><?php echo $cpu_load[0]; ?></strong>
                </div>
                <div style="flex: 1; min-width: 150px; background: #222; padding: 10px; border-radius: 5px;">
                    <span style="color: #888;">RAM</span><br>
                    <strong><?php echo $ram_usage; ?>%</strong>
                </div>
                <div style="flex: 1; min-width: 150px; background: #222; padding: 10px; border-radius: 5px;">
                    <span style="color: #888;">Uptime</span><br>
                    <strong><?php echo $uptime; ?></strong>
                </div>
            </div>
        </div>

        <!-- Contact -->
        <div class="card">
            <h3><i class="fas fa-shopping-cart"></i> Buy Token / Script</h3>
            <p>Untuk membuat akun, Anda memerlukan <b>Token</b>. Silahkan beli ke Admin.</p>
            <div style="display: flex; justify-content: space-between;">
                <a href="https://wa.me/6287733745059" class="contact-btn wa"><i class="fab fa-whatsapp"></i> WhatsApp</a>
                <a href="https://t.me/otomotif_digital" class="contact-btn tg"><i class="fab fa-telegram"></i> Telegram</a>
            </div>
        </div>

        <!-- Create Account -->
        <div class="card">
            <h3><i class="fas fa-user-plus"></i> Create New Account</h3>
            <?php if($error) echo "<p style='color:red;'>$error</p>"; ?>
            <form method="POST">
                <input type="hidden" name="action" value="create_account">
                <input type="text" name="username" placeholder="Username (e.g. Budi)" required>
                <select name="days">
                    <option value="30">30 Days</option>
                    <option value="60">60 Days</option>
                </select>
                <input type="text" name="token" placeholder="Paste TOKEN here..." required style="border-color: var(--gold);">
                <button type="submit">CREATE ACCOUNT</button>
            </form>
        </div>

        <!-- Account List -->
        <div class="card">
            <h3><i class="fas fa-list"></i> Active Accounts</h3>
            <table>
                <?php foreach($users as $u): if($u['username']=='admin') continue; ?>
                <tr>
                    <td>
                        <strong style="font-size: 1.1rem;"><?php echo htmlspecialchars($u['username']); ?></strong><br>
                        <span style="color:#aaa; font-size:0.8rem;">Exp: <?php echo $u['exp_date']; ?></span>
                    </td>
                    <td style="text-align: right;">
                        <span class="status-active">ACTIVE</span><br><br>
                        <!-- Only pass Username, not UUID/PIN -->
                        <button onclick="openLinkModal('<?php echo htmlspecialchars($u['username'], ENT_QUOTES); ?>')" style="padding: 5px 10px; width: auto; font-size: 0.8rem; background: #333; color: #fff; border: 1px solid #555;">View Config</button>
                    </td>
                </tr>
                <?php endforeach; ?>
            </table>
        </div>

        <div style="text-align: center; color: #555; font-size: 0.8rem;">
            <p>Sewa Script VPN Auto-Install? Hubungi Admin.</p>
        </div>
    </div>

    <!-- PIN Modal -->
    <div id="pinModal" class="modal">
        <div class="modal-content">
            <h3>Security Verification</h3>
            <p>Masukkan 6-Digit PIN (Owner ID) untuk melihat config akun ini.</p>
            <input type="number" id="pinInput" placeholder="123456" style="text-align: center; font-size: 1.2rem; letter-spacing: 5px;">
            <button onclick="verifyPin()">UNLOCK CONFIG</button>
            <br><br>
            <button onclick="closeModal('pinModal')" style="background: #333; color: #fff;">CANCEL</button>
        </div>
    </div>

    <!-- Config Modal -->
    <div id="configModal" class="modal">
        <div class="modal-content">
            <h3 style="color: var(--gold);">Connection Links</h3>
            <div style="margin-bottom: 10px;">
                <button onclick="setProto('vless')" style="width:30%; background:#444; color:#fff;">VLESS</button>
                <button onclick="setProto('vmess')" style="width:30%; background:#444; color:#fff;">VMess</button>
                <button onclick="setProto('trojan')" style="width:30%; background:#444; color:#fff;">Trojan</button>
            </div>
            <div id="qrcode" style="background: white; padding: 10px; margin: 10px auto; width: fit-content;"></div>
            <textarea id="configText" style="width:100%; height:80px; background:#111; color:#0f0; border:1px solid #444;" readonly></textarea>
            <button onclick="closeModal('configModal')" style="margin-top:10px;">CLOSE</button>
        </div>
    </div>

    <script>
        let selectedUser = '';
        let fetchedUuid = ''; // populated from server
        let host = '<?php echo $domain; ?>';
        let currentProto = 'vless';

        function openLinkModal(username) {
            selectedUser = username;
            document.getElementById('pinInput').value = '';
            document.getElementById('pinModal').style.display = 'flex';
        }

        function verifyPin() {
            let pin = document.getElementById('pinInput').value;
            // AJAX to Server
            let formData = new FormData();
            formData.append('action', 'get_config');
            formData.append('username', selectedUser);
            formData.append('pin', pin);

            fetch('index.php', { method: 'POST', body: formData })
            .then(r => r.json())
            .then(data => {
                if(data.status === 'ok') {
                    fetchedUuid = data.uuid;
                    closeModal('pinModal');
                    document.getElementById('configModal').style.display = 'flex';
                    setProto('vless');
                } else {
                    alert('PIN SALAH!');
                }
            });
        }

        function closeModal(id) { document.getElementById(id).style.display = 'none'; }

        function setProto(proto) {
            currentProto = proto;
            generate();
        }

        function generate() {
            const port = "443";
            const path = "/" + currentProto;
            let link = "";

            if (currentProto === "vless") {
                link = `vless://${fetchedUuid}@${host}:${port}?path=${path}&security=tls&encryption=none&type=ws&host=${host}&sni=${host}#${host}-VLESS`;
            } else if (currentProto === "trojan") {
                link = `trojan://${fetchedUuid}@${host}:${port}?path=${path}&security=tls&type=ws&host=${host}&sni=${host}#${host}-Trojan`;
            } else if (currentProto === "vmess") {
                const vmessJson = { v: "2", ps: `${host}-VMess`, add: host, port: port, id: fetchedUuid, aid: "0", scy: "auto", net: "ws", type: "none", host: host, path: path, tls: "tls", sni: host };
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
echo -e "${GREEN}       VPS AUTO INSTALLER COMPLETE!       ${PLAIN}"
echo -e "${GREEN}==========================================${PLAIN}"
echo -e "Dashboard: https://$DOMAIN"
echo -e "Admin Login: https://$DOMAIN/admin_login.php"
echo -e "Admin Pass: $UUID"
echo -e "=========================================="
