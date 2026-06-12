# SeaweedFS + Caddy — Rootful Podman Quadlet
> Fedora · SELinux enforcing · Let's Encrypt ACME · Rootful systemd

---

## Architecture

```
Internet (80/443)
    │
    ▼
┌─────────────────────────────────┐
│  Caddy container                │  /var/lib/caddy/
│  TLS termination + ACME         │
│  <IP_ADDRESS>:80, :443           │
└────────────┬────────────────────┘
             │ seaweedfs-net (internal DNS)
             ▼
┌─────────────────────────────────┐
│  SeaweedFS container (weed mini)│  /data/seaweedfs/
│  127.0.0.1 only, no public port │
│  :9333  master                  │
│  :8888  filer                   │
│  :8333  S3 API                  │
│  :23646 admin web UI            │
└─────────────────────────────────┘
```

- SeaweedFS is never exposed publicly — only reachable via Caddy over the internal `seaweedfs-net` network
- Caddy handles Let's Encrypt certificate issuance and renewal automatically (HTTP-01 challenge)
- Both containers managed by systemd via Podman Quadlet, start on boot automatically
- Admin UI password delivered via Podman secret as env var — never stored in unit files or on disk as plaintext

---

## Prerequisites

- Fedora host with `podman` installed (`dnf install -y podman`)
- Two public DNS A records pointing to your host's public IP:
  - `s3.yourdomain.com`
  - `s3-admin.yourdomain.com`
- Ports 80 and 443 reachable from the internet (required for ACME HTTP-01 challenge and HTTPS)
- All commands run as **root**

---

## Directory Structure

```
/etc/containers/systemd/
├── seaweedfs-net.network
├── seaweedfs.container
└── caddy.container

/data/seaweedfs/
├── data/                        # SeaweedFS object storage (UID 1000 at runtime)
│   └── start.sh                 # Entrypoint wrapper script
└── config/
    └── security.toml            # JWT keys + CORS (mode 600)

/var/lib/caddy/
├── Caddyfile
├── data/                        # Let's Encrypt certs — NEVER delete
└── config/                      # Caddy runtime state
```

---

## Step 1 — Create Directories

```bash
mkdir -p /data/seaweedfs/{data,config}
mkdir -p /var/lib/caddy/{data,config}
mkdir -p /etc/seaweedfs
chmod 700 /etc/seaweedfs
```

---

## Step 2 — Create Podman Secret (Admin UI Password)

```bash
printf '%s' "$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 32)" \
  | podman secret create seaweedfs_admin_password -

# Verify
podman secret ls
```

---

## Step 3 — Write security.toml

Generate two random 32-character JWT signing keys:

```bash
cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 32; echo
cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 32; echo
```

```bash
cat > /data/seaweedfs/config/security.toml << 'EOF'
[cors.allowed_origins]
values = "https://s3-admin.yourdomain.com"

[jwt.signing]
key = "REPLACE_WITH_FIRST_RANDOM_STRING"

[jwt.filer_signing]
key = "REPLACE_WITH_SECOND_RANDOM_STRING"
EOF

chmod 600 /data/seaweedfs/config/security.toml
chown 1000:1000 /data/seaweedfs/config/security.toml
chcon -t container_file_t /data/seaweedfs/config/security.toml
```

---

## Step 4 — Write start.sh

```bash
cat > /data/seaweedfs/data/start.sh << 'EOF'
#!/bin/sh
exec /entrypoint.sh mini -s3 \
  -admin.user=admin \
  -admin.password="$ADMIN_PASSWORD"
EOF

chmod 755 /data/seaweedfs/data/start.sh
chown 1000:1000 /data/seaweedfs/data/start.sh
```

---

## Step 5 — Write Caddyfile

```bash
cat > /var/lib/caddy/Caddyfile << 'EOF'
{
    email your-real@email.com
}

s3-admin.yourdomain.com {
    reverse_proxy seaweedfs:23646
}

s3.yourdomain.com {
    reverse_proxy seaweedfs:8333
}
EOF

chmod 644 /var/lib/caddy/Caddyfile
```

---

## Step 6 — Write Quadlet Files

### `/etc/containers/systemd/seaweedfs-net.network`

```bash
cat > /etc/containers/systemd/seaweedfs-net.network << 'EOF'
[Unit]
Description=SeaweedFS private network

[Network]
NetworkName=seaweedfs-net
EOF
```

### `/etc/containers/systemd/seaweedfs.container`

```bash
cat > /etc/containers/systemd/seaweedfs.container << 'EOF'
[Unit]
Description=SeaweedFS (weed mini)
After=seaweedfs-net-network.service
Requires=seaweedfs-net-network.service

[Container]
Image=docker.io/chrislusf/seaweedfs:latest
ContainerName=seaweedfs

PublishPort=127.0.0.1:9333:9333
PublishPort=127.0.0.1:8888:8888
PublishPort=127.0.0.1:8333:8333
PublishPort=127.0.0.1:23646:23646

Network=seaweedfs-net

Volume=/data/seaweedfs/data:/data:z
Volume=/data/seaweedfs/config/security.toml:/etc/seaweedfs/security.toml:ro,z

Secret=seaweedfs_admin_password,type=env,target=ADMIN_PASSWORD

Entrypoint=/bin/sh
Exec=/data/start.sh

DropCapability=all
AddCapability=SETUID
AddCapability=SETGID
AddCapability=CHOWN

[Service]
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

chmod 600 /etc/containers/systemd/seaweedfs.container
```

### `/etc/containers/systemd/caddy.container`

```bash
cat > /etc/containers/systemd/caddy.container << 'EOF'
[Unit]
Description=Caddy reverse proxy (ACME/TLS)
After=seaweedfs-net-network.service seaweedfs.service
Requires=seaweedfs-net-network.service

[Container]
Image=docker.io/library/caddy:alpine
ContainerName=caddy

PublishPort=<IP_ADDRESS>:80:80
PublishPort=<IP_ADDRESS>:443:443
PublishPort=<IP_ADDRESS>:443:443/udp

Network=seaweedfs-net

Volume=/var/lib/caddy/Caddyfile:/etc/caddy/Caddyfile:ro,Z
Volume=/var/lib/caddy/data:/data:Z
Volume=/var/lib/caddy/config:/config:Z

DropCapability=all
AddCapability=NET_BIND_SERVICE
AddCapability=NET_ADMIN

[Service]
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
```

---

## Step 7 — Open Firewall

```bash
firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=https --permanent
firewall-cmd --reload
```

---

## Step 8 — Pull Images

```bash
podman pull docker.io/chrislusf/seaweedfs:latest
podman pull docker.io/library/caddy:alpine
```

---

## Step 9 — Validate Quadlet (Dry Run)

```bash
systemctl daemon-reload
/usr/libexec/podman/quadlet -dryrun 2>&1 | grep -E "(seaweedfs|caddy)"
```

All three units must appear without parse errors before proceeding.

---

## Step 10 — Start Services

```bash
systemctl start seaweedfs-net-network.service
systemctl start seaweedfs.service
systemctl start caddy.service

# Verify all running
systemctl status seaweedfs-net-network.service seaweedfs.service caddy.service
podman ps
```

---

## Step 11 — Verify TLS

Watch Caddy obtain certificates (takes a few seconds per domain):

```bash
journalctl -u caddy.service -f
```

Then confirm both certs are valid:

```bash
echo | openssl s_client -servername s3-admin.yourdomain.com \
  -connect s3-admin.yourdomain.com:443 2>/dev/null \
  | openssl x509 -noout -subject -dates

echo | openssl s_client -servername s3.yourdomain.com \
  -connect s3.yourdomain.com:443 2>/dev/null \
  | openssl x509 -noout -subject -dates
```

Both should show `issuer=C=US, O=Let's Encrypt`.

---

## Security Posture

| Control | Implementation |
|---|---|
| SeaweedFS not exposed publicly | `PublishPort=127.0.0.1:…` — loopback only |
| Container network isolation | Dedicated `seaweedfs-net`, no bridge to default network |
| Caddy bound to specific interface | `PublishPort=<IP_ADDRESS>:…` |
| No root inside containers at runtime | `su-exec` drops to UID 1000 (`seaweed`) after chown |
| Capabilities minimised | SeaweedFS: `SETUID,SETGID,CHOWN` only; Caddy: `NET_BIND_SERVICE,NET_ADMIN` only |
| SELinux enforcing | `:z` shared label on SeaweedFS data; `:Z` private label on Caddy volumes |
| Admin UI password | Podman secret → env var injection; never in unit file or on disk as plaintext |
| JWT internal auth | `security.toml` signing keys prevent unauthenticated internal writes |
| CORS lockdown | `allowed_origins` scoped to admin domain only |
| TLS cert lifecycle | Caddy ACME auto-renewal, no manual steps |

---

## Day-2 Operations

### Logs

```bash
journalctl -u seaweedfs.service -f
journalctl -u caddy.service -f
```

### Shell into container

```bash
podman exec -it seaweedfs /bin/sh
podman exec -it caddy /bin/sh
```

### Reload Caddy config after Caddyfile edit

```bash
podman exec caddy caddy reload --config /etc/caddy/Caddyfile
```

### Restart a service

```bash
systemctl restart seaweedfs.service
systemctl restart caddy.service
```

### Update container images

```bash
podman pull docker.io/chrislusf/seaweedfs:latest
podman pull docker.io/library/caddy:alpine
systemctl restart seaweedfs.service
systemctl restart caddy.service
```

### Rotate admin password

```bash
podman secret rm seaweedfs_admin_password
printf '%s' "$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 32)" \
  | podman secret create seaweedfs_admin_password -
systemctl restart seaweedfs.service
```

### Inspect generated systemd unit

```bash
cat /run/systemd/generator/seaweedfs.service
cat /run/systemd/generator/caddy.service
```

---

## TLS Certificate Renewal

Renewal is fully automatic — Caddy renews certificates approximately 30 days before expiry with no manual steps required. Requirements for renewal to succeed:

- Port 80 must remain reachable from the internet at renewal time (HTTP-01 challenge)
- `/var/lib/caddy/data/` must never be deleted (stores certs, keys, ACME account)
- `caddy.service` must be running

---

## Troubleshooting

| Symptom | Check |
|---|---|
| SeaweedFS permission denied on `/data` | `ls -lZ /data/seaweedfs/data` — confirm `container_file_t` label |
| SeaweedFS `su-exec: setgroups` error | Missing `SETGID` capability — check `AddCapability=` lines |
| Caddy can't reach `seaweedfs:23646` | `podman network inspect seaweedfs-net` — both containers must be listed |
| ACME challenge fails | Port 80 not reachable from internet — check router NAT and `firewall-cmd --list-services` |
| Auth not enabled on admin UI | `journalctl -u seaweedfs.service | grep -i auth` — must show `Authentication: Enabled` |
| Quadlet changes not picked up | `systemctl daemon-reload` then restart the service |
| SELinux AVC denial | `ausearch -m avc -ts recent` — check label on affected file |