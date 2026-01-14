#!/bin/bash
# VPanel Auto-Updater
# Fetches install.sh from repo and extracts the PHP Dashboard parts

REPO_URL="https://raw.githubusercontent.com/2026musik-code/ofs/main/vps-installer/install.sh"
TEMP_FILE="/tmp/vpanel_install_update.sh"

echo "Checking for updates..."

# 1. Download the latest install script
if curl -s -f -o "$TEMP_FILE" "$REPO_URL"; then
    echo "Download success."

    # 2. Extract index.php
    # We use sed to grab content between the cat HEREDOC markers
    # Pattern: from "cat > /var/www/vpanel/index.php <<'PHP'" to "^PHP$"
    # Then remove the first and last line (the markers themselves)
    sed -n "/cat > \/var\/www\/vpanel\/index.php <<'PHP'/,/^PHP$/p" "$TEMP_FILE" | sed '1d;$d' > /var/www/vpanel/index.php

    # 3. Extract login.php (Just in case)
    sed -n "/cat > \/var\/www\/vpanel\/login.php <<'PHP'/,/^PHP$/p" "$TEMP_FILE" | sed '1d;$d' > /var/www/vpanel/login.php

    echo "Dashboard updated successfully!"
    rm -f "$TEMP_FILE"
else
    echo "Error: Failed to download update script from GitHub."
    exit 1
fi
