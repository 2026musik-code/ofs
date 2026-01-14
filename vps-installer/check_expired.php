<?php
// Check for expired users
$users_file = '/etc/vpanel_users.json';
$xray_config = '/usr/local/etc/xray/config.json';

if(!file_exists($users_file)) exit;

$users = json_decode(file_get_contents($users_file), true);
$today = date('Y-m-d');
$changed = false;
$new_users = [];

foreach($users as $u) {
    // If admin, keep
    if($u['username'] === 'admin') {
        $new_users[] = $u;
        continue;
    }

    // Check expiry
    if(isset($u['exp_date']) && $u['exp_date'] < $today) {
        $changed = true;
        // Logic to log deletion or notify could go here
        echo "Deleting expired user: " . $u['username'] . "\n";
    } else {
        $new_users[] = $u;
    }
}

if($changed) {
    // Save Users
    file_put_contents($users_file, json_encode($new_users, JSON_PRETTY_PRINT));

    // Update Xray
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

    // Restart Xray
    shell_exec('sudo systemctl restart xray');
    echo "Expired users removed and service restarted.\n";
}
?>
