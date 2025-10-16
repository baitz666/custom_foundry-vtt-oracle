#!/usr/bin/env bash
set -euo pipefail
REPO_RAW="https://raw.githubusercontent.com/<YOUR_GH_USER>/mythos-foundry-oracle/main"

# ==== Basics: update system, remove older packages; install gnupg, unzip, nano ====
sudo apt update && sudo apt -y upgrade && sudo apt autoremove -y && sudo apt autoclean
sudo apt -y install ca-certificates curl gnupg unzip nano

# ==== Node 22 LTS + PM2 (recommended for Foundry 11/12/13) ====
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
  | sudo tee /etc/apt/sources.list.d/nodesource.list
sudo apt update && sudo apt -y install nodejs
sudo npm i -g pm2
pm2 update
pm2 startup
sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u ubuntu --hp /home/ubuntu

# ==== Create needed directories ====
mkdir -p ~/foundry ~/foundryuserdata

# ==== Download Foundry (Node build) ====
echo "Paste the Foundry timed NodeJS download URL:"
read -r TDURL
wget -O ~/foundry/foundryvtt.zip "$TDURL"
unzip -o ~/foundry/foundryvtt.zip -d ~/foundry
rm -f  ~/foundry/foundryvtt.zip

# ==== Locate the proper entrypoint (flat vs nested layout) ====
# ENTRY should now point to Foundry's main.js
if [[ -f "$HOME/foundry/resources/app/main.js" ]]; then
  ENTRY="$HOME/foundry/resources/app/main.js"
elif [[ -f "$HOME/foundry/main.js" ]]; then
  ENTRY="$HOME/foundry/main.js"
else
  # Fallback: search but ignore node_modules
  ENTRY="$(find "$HOME/foundry" -type f -name 'main.js' ! -path '*node_modules*' | head -n1)"
fi
if [[ -z "${ENTRY:-}" || ! -f "$ENTRY" ]]; then
  echo "ERROR: Could not find Foundry entrypoint (main.js)."
  exit 1
fi

# ==== First PM2 run (bind to localhost only) ====
pm2 start "node $ENTRY --dataPath=/home/ubuntu/foundryuserdata --port=30000 --hostname=127.0.0.1" --name foundry
pm2 save

# (Optional) Small priority boost
sudo renice -n -5 -p "$(pgrep -f "$ENTRY" | head -1)" || true

# ==== Caddy (reverse proxy with auto-HTTPS) ====
sudo apt -y install debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt -y install caddy

echo "Enter the public hostname players will use (e.g., mythos-vtt.ddns.net):"
read -r DOMAIN

# Fetch main Caddyfile from GitHub
curl -fsSL "$REPO_RAW/caddy/Caddyfile" -o /tmp/Caddyfile
# (Optional) fetch CDN snippet but don't import it yet
# curl -fsSL "$REPO_RAW/caddy/snippets/cdn.caddy" -o /etc/caddy/snippets/cdn.caddy

# Replace placeholder with your domain (keep a clear token in the file, e.g. YOUR_DOMAIN)
sudo sed "s/YOUR_DOMAIN/${DOMAIN}/g" /tmp/Caddyfile | sudo tee /etc/caddy/Caddyfile >/dev/null
sudo systemctl enable --now caddy

# Validate & reload Caddy
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy || sudo systemctl restart caddy

# ==== Tell Foundry it’s behind HTTPS (wait until options.json exists) ====
OPTS=/home/ubuntu/foundryuserdata/Config/options.json
echo "Waiting for $OPTS to be created by Foundry (first run)..."
for i in {1..30}; do
  [[ -f "$OPTS" ]] && break
  sleep 2
done
if [[ -f "$OPTS" ]]; then
  sed -i 's/"proxyPort": null/"proxyPort": 443/g' "$OPTS"
  sed -i 's/"proxySSL": false/"proxySSL": true/g' "$OPTS"
  # Optional: lock hostname into Foundry (helps invites/absolute URLs)
  # jq -r --arg h "$DOMAIN" '.hostname=$h' "$OPTS" > "$OPTS.tmp" && mv "$OPTS.tmp" "$OPTS"
  pm2 restart foundry
else
  echo "WARNING: $OPTS not found yet. Start Foundry once and re-run the two sed lines."
fi

echo "Done. Give Caddy ~30-60s to issue the cert, then open: https://${DOMAIN}"
echo "TIP: Once HTTPS works, close public port 30000 in OCI; keep only 22,80,443."
echo "Restarting system to complete installation"
sleep 60
sudo shutdown -r now