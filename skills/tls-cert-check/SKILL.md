---
name: tls-cert-check
description: Check TLS certificates on an Ubuntu server — Let's Encrypt / certbot certificates and their renewal timer, certificate files referenced by nginx, Apache, Postfix and other services, what a live endpoint actually serves (expiry, chain, hostname match), and certificates expiring within 30 days — and diagnose failed renewals. Use when the user asks "when do my certificates expire", "is certbot renewing", "check the SSL cert on <host>", "certificate expired / renewal failed", or "which certs are on this server".
---

# TLS certificate check

Read-only, except `certbot renew` when the user asks to fix a renewal.

## 1. certbot / Let's Encrypt

```bash
command -v certbot && sudo certbot certificates          # names, domains, expiry, paths
systemctl list-timers --no-pager | grep -E 'certbot|snap.certbot'
sudo journalctl -u certbot -u snap.certbot.renew --since -14d --no-pager | tail -30
sudo tail -40 /var/log/letsencrypt/letsencrypt.log
```

Ubuntu has two installs: the snap (`snap.certbot.renew.timer`, recommended upstream)
and the apt package (`certbot.timer`). Both renew certificates within 30 days of
expiry, twice a day. If both are installed, report it (they share `/etc/letsencrypt`;
harmless but confusing). Dry-run a renewal to prove it works without spending the
rate limit:

```bash
sudo certbot renew --dry-run
```

Common failures: port 80 blocked (HTTP-01 needs it from the internet: check ufw and
the cloud firewall), DNS no longer points here, the webroot path changed, a DNS
plugin's API credential expired, or a `--pre-hook`/`--post-hook` failing. Renewal
config per cert: `/etc/letsencrypt/renewal/<name>.conf`.

## 2. Certificates on disk

```bash
for f in /etc/letsencrypt/live/*/cert.pem; do
  printf '%s  ' "$f"; sudo openssl x509 -in "$f" -noout -enddate -subject | paste -sd' '; done 2>/dev/null
sudo grep -rhoE '(ssl_certificate|SSLCertificateFile|smtpd_tls_cert_file|ssl_cert)\s*=?\s*[^;[:space:]]+' \
  /etc/nginx /etc/apache2 /etc/postfix /etc/dovecot 2>/dev/null | awk '{print $NF}' | tr -d '<' | sort -u
```

For each file, `sudo openssl x509 -in <file> -noout -subject -issuer -enddate -ext subjectAltName`.
`openssl x509 -checkend 2592000 -noout -in <file>` exits non-zero if it expires within
30 days.

## 3. What a live endpoint serves

What the server presents can differ from the files (service not reloaded after renewal,
wrong vhost, a proxy in front):

```bash
echo | openssl s_client -connect <host>:443 -servername <host> 2>/dev/null \
  | openssl x509 -noout -subject -issuer -enddate -ext subjectAltName
echo | openssl s_client -connect <host>:443 -servername <host> -verify_return_error 2>&1 | grep -E 'Verify return code|verify error'
```

Other ports: `:465`/`:993` (direct TLS), `-starttls smtp -connect <host>:587`,
`-starttls imap`. If the file on disk is newer than what the endpoint serves, the
service needs a reload (`systemctl reload nginx`); certbot does this only if a deploy
hook is configured (`/etc/letsencrypt/renewal-hooks/deploy/`).

If the host is behind a CDN or tunnel (Cloudflare, etc.), the public certificate is the
CDN's; check the origin certificate separately by connecting to the origin address.

## Report

Table: certificate (name / domains), source (certbot, file, endpoint), expires (date
and days left), issuer, auto-renew yes/no. Flag anything under 30 days, any expired,
hostname mismatches, and endpoint ≠ file.
