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
