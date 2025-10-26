# Foundry VTT on Oracle Free Tier (Caddy + PM2)

One-shot installer to deploy **Foundry VTT** on an **Oracle Cloud Always Free** VM with:

* **Node 22** runtime
* **PM2** process manager (auto-start on boot)
* **Caddy** reverse proxy with HTTPS (Let’s Encrypt), HTTP/2, compression, and static caching
* Foundry bound to **localhost:30000** (safe behind Caddy on 443)

> Inspired by and adapted from: [aco-rt/Foundry-VTT-Oracle](https://github.com/aco-rt/Foundry-VTT-Oracle)

---

## Repo layout

```
.
├─ scripts/
│  └─ foundryOracle.sh         # Main installer (curl + run)
└─ caddy/
   ├─ Caddyfile                 # Reverse proxy, TLS, headers, caching
   └─ snippets/
      └─ cdn.caddy             # (Optional) Redirect heavy static paths to a CDN
```

---

## What the installer does

1. Updates Ubuntu, installs **Node 22**, **PM2**, **curl/unzip**.
2. Creates `~/foundry` and `~/foundryuserdata`.
3. Prompts you for the **Foundry timed download URL**, downloads/unzips the Node build.
4. Detects Foundry’s `main.js` and starts it with PM2 on **127.0.0.1:30000**.
5. Installs **Caddy**, fetches this repo’s **Caddyfile**, substitutes your domain, formats/validates it, and enables the service.
6. Waits for `options.json` then sets `proxySSL=true` and `proxyPort=443` (with a jq fallback if needed).
7. Prints final instructions and reboots.

---

## Requirements

* **Oracle Cloud VM** (Always Free works great)

  * Recommended shape: **VM.Standard.A1.Flex** (Ampere ARM).
  * Ubuntu LTS (20.04/22.04/24.04).
  * **Public IPv4** assigned to the VNIC.
* **Networking (ingress rules)**: open **TCP 22, 80, 443**.

  * Optionally open **TCP 30000** only while testing; close it after HTTPS is working.
* A **DNS name** pointing to your VM’s public IP (No-IP DDNS works; or reserve a public IP in OCI).

---

## Quickstart (on the VM)

SSH in as `ubuntu@<public-ip-or-hostname>`, then:

```bash
# 1) Download the installer from this repo
curl -fsSL https://raw.githubusercontent.com/baitz666/foundryOracle/main/scripts/foundryOracle.sh -o foundryOracle.sh
chmod +x foundryOracle.sh

# 2) Run it (this tells the script where to fetch the Caddyfile/snippet from)
./foundryOracle.sh
```

During the run you’ll be asked for:

* **Foundry timed NodeJS download URL** (from your Foundry account)
* **Public hostname** (e.g., `mythos-vtt.ddns.net`)

When it finishes, give Caddy ~30–60 seconds to fetch a cert, then visit:

```
https://<your-domain>
```

> After HTTPS works, **close port 30000** in OCI. Foundry listens only on 127.0.0.1 and is safely proxied by Caddy.

---

## PM2 cheatsheet

```bash
pm2 status
pm2 logs foundry --lines 100
pm2 restart foundry
pm2 stop foundry
pm2 delete foundry
pm2 save      # persist current PM2 process list (already done by the script)
```

---

## Updating Foundry later

When a new version is released:

```bash
read -p "Paste new Foundry timed URL: " TDURL
wget -O ~/foundry/foundryvtt.zip "$TDURL"
unzip -o ~/foundry/foundryvtt.zip -d ~/foundry
rm -f ~/foundry/foundryvtt.zip
pm2 restart foundry
```

Caddy doesn’t need changes for Foundry updates.

---

## Optional: set a canonical hostname in Foundry

The installer already sets `proxySSL=true` and `proxyPort=443`.
If you ever find invite links are wrong, you can also pin the hostname:

```bash
OPTS=/home/ubuntu/foundryuserdata/Config/options.json
sudo apt -y install jq
TMP="$(mktemp)"
jq --arg host "<your-domain>" '.hostname=$host | .proxyPort=443 | .proxySSL=true' "$OPTS" > "$TMP" \
  && sudo mv "$TMP" "$OPTS"
pm2 restart foundry
```

---

## Optional: enable the CDN redirect (later)

If you host heavy assets (maps, modules, worlds, fonts) on a CDN/S3/R2:

1. Point `cdn.<your-domain>` to your bucket/CDN URL.
2. Edit `/etc/caddy/Caddyfile` and **uncomment**:

   ```caddy
   import /etc/caddy/snippets/cdn.caddy
   ```
3. Reload:

   ```bash
   sudo caddy validate --config /etc/caddy/Caddyfile
   sudo systemctl reload caddy
   ```

The snippet redirects `/assets/* /modules/* /systems/* /worlds/* /fonts/*` to `https://cdn.<your-domain>{uri}` (302 while testing—flip to 301 when happy).

---

## Troubleshooting

* **502 Bad Gateway** in browser

  * `pm2 status` → is `foundry` online?
  * `ss -tulpn | grep 30000` → should show `127.0.0.1:30000`
  * `journalctl -u caddy -n 100 --no-pager` for Caddy logs

* **TLS/cert not issued**

  * Ports **80/443** must be open to the internet.
  * DNS must resolve your hostname to the VM’s **public IP**.
  * Try `sudo caddy validate --config /etc/caddy/Caddyfile` and check logs.

* **`options.json` wasn’t found**

  * Start Foundry once in the browser so it creates `~/foundryuserdata/Config/options.json`, then re-run the two lines that set `proxyPort`/`proxySSL` (or use the jq snippet above).

* **Migrating from testing**

  * Once HTTPS works, **close port 30000** in Oracle. Keep 22/80/443.

---

## Backups (basic)

* App data lives in: `~/foundryuserdata`
* Quick snapshot:

  ```bash
  tar czf ~/foundry-backup-$(date +%F).tgz ~/foundryuserdata /etc/caddy/Caddyfile
  ```
* Consider OCI volume backups or snapshots for the boot/attached volumes.

---

## Security notes

* Foundry is **not** exposed on a public interface; only Caddy (443) is.
* `Strict-Transport-Security`, `X-Frame-Options`, and `Referrer-Policy` headers are set in the Caddyfile.
* Keep your system updated: `sudo apt update && sudo apt upgrade -y`.

---

## Non-interactive run (optional)

If you need to avoid prompts, you can pipe answers:

```bash
# First line: Foundry timed URL
# Second line: your domain
printf '%s\n%s\n' "https://example.com/foundry-timed-url.zip" "mythos-vtt.ddns.net" \
  | sudo -E REPO_RAW="https://raw.githubusercontent.com/baitz666/foundryOracle/main" ./foundryOracle.sh
```

---

## Credits & License

* Based on ideas from [aco-rt/Foundry-VTT-Oracle](https://github.com/aco-rt/Foundry-VTT-Oracle).
* This repo’s code is provided “as is”, no warranty. Use at your own risk.
* (Add your preferred license here, e.g., MIT.)

---

## Support

Open an issue with:

* Your Oracle shape/Ubuntu version
* Output of:

  ```bash
  pm2 status
  journalctl -u caddy -n 100 --no-pager
  sudo caddy validate --config /etc/caddy/Caddyfile
  ```
* And your domain (or confirm DNS resolves to your VM’s public IP)

---

That’s it—your README now documents what each piece does and gives a smooth path from a fresh VM to a hardened, HTTPS Foundry.
