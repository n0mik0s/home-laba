# Infrastructure — Libvirt VM Provisioning

## Overview

Terraform project that provisions KVM/QEMU virtual machines on a bare-metal Fedora Server 43 host using the [dmacvicar/libvirt](https://registry.terraform.io/providers/dmacvicar/libvirt/latest) provider. Cloud-init handles first-boot configuration of each VM (user, networking, packages, firewall).

## Hardware

| Resource | Spec |
|---|---|
| Host | 1 × bare-metal server |
| CPU | 40 cores |
| RAM | 256 GB (listed as 256 MB in spec — verify before sizing VMs) |
| Disk | 3 TB HDD |
| OS | Fedora Server ≥ 43 |

## Software Stack

| Tool | Version |
|---|---|
| Terraform | ≥ 1.9.x (latest stable 1.x; no alpha/beta/RC) |
| dmacvicar/libvirt provider | `>= 0.9.8` (exact version pinned in `.terraform.lock.hcl`) |
| Guest OS (default) | Ubuntu 24.04 LTS (Noble Numbat) |
| Guest OS (freeipa VM) | Fedora Server Cloud Base, latest stable (`os = "fedora"`, see [Per-VM Operating System](#per-vm-operating-system-os)) |
| libvirt / KVM | Fedora 43 repo packages |
| FreeIPA | `freeipa.ansible_freeipa` Ansible collection (`>= 1.14.0`) — see [FreeIPA Ansible Project](#freeipa-ansible-project-ansiblefreeipa-ansible) |

Always use the latest **LTS or stable** release. Never use alpha/beta/RC in any environment.

The 0.9.8 provider is a plugin-framework rewrite: resource attributes use object syntax (`foo = { bar = ... }`), not the legacy nested blocks from 0.8.x. See [libvirt_domain Schema Notes](#libvirt_domain-schema-notes-09x-provider) below for the quirks this surfaced.

## Directory Structure

```
terraform/
├── laba/                       # "laba" environment — root module
│   ├── main.tf                 # Wires all sub-modules together
│   ├── provider.tf             # Provider + Terraform version constraints
│   ├── variables.tf            # Root input variables
│   ├── outputs.tf               # Root outputs (network, pool, VM names/IPs)
│   ├── backend.tf              # S3-compatible state backend
│   ├── config.tfvars           # Environment variable values (no secrets)
│   ├── .terraform.lock.hcl     # Provider lock file — always commit this
│   └── cloud-init/
│       ├── user-data.yaml.tftpl         # Cloud-init user-data template (Ubuntu, os = "ubuntu")
│       ├── user-data-fedora.yaml.tftpl  # Cloud-init user-data template (Fedora, os = "fedora")
│       └── network-config.yaml.tftpl    # Cloud-init network config template (v2, shared)
└── modules/
    ├── libvirt_cloudinit_disk/
    ├── libvirt_domain/
    ├── libvirt_network/
    ├── libvirt_pool/
    └── libvirt_volume/

ansible/
└── freeipa-ansible/            # Standalone FreeIPA server install/config (see "FreeIPA Ansible Project" below)
    ├── ansible.cfg
    ├── requirements.yml
    ├── inventory/hosts.ini
    ├── group_vars/
    │   ├── ipaserver.yml
    │   └── ipaserver/vault.yml.example
    ├── playbook.yml
    └── README.md
```

Each environment (e.g. `laba`) is its own root module with its own state and backend. New environments are added as sibling directories under `terraform/` (e.g. `terraform/staging/`), reusing the same `modules/`.

## Module Architecture

**One module per libvirt provider resource type.** Modules must not encode VM roles; roles are expressed in the root module by composing these building blocks.

| Module | Wraps libvirt resource | Responsibility |
|---|---|---|
| `libvirt_pool` | `libvirt_pool` | Dir-type storage pool at a configurable host path |
| `libvirt_volume` | `libvirt_volume` | Base image download, per-VM qcow2 overlay, and extra data disks |
| `libvirt_network` | `libvirt_network` | Bridge network attached to a configurable host bridge |
| `libvirt_cloudinit_disk` | `libvirt_cloudinit_disk` | Cloud-init ISO from rendered user-data + network-config |
| `libvirt_domain` | `libvirt_domain` | VM definition (CPU, RAM, disks, network, console, cloud-init) |

### Resource Naming Convention

All managed resources use: `${var.project_name}-${var.vm_name}` (the libvirt network uses just `var.project_name`).

Example for the `laba` project's `freeipa` VM: `laba-freeipa` (volume, domain, cloud-init ISO). Extra data-disk volumes append an index: `laba-gitlab-data0`, `laba-gitlab-data1`, ...

### Module File Layout

Every module must have exactly these four files — no more:

```
modules/<name>/
├── main.tf        # resource or data block(s) only
├── variables.tf   # all inputs, typed correctly, with meaningful descriptions
├── outputs.tf     # outputs consumed by root or sibling modules
└── provider.tf    # required_providers (inherit versions from root, no constraints here)
```

## Terraform State Backend — S3-Compatible

State is stored in an S3-compatible bucket (locking via the bucket's native S3 lock support). Configured in `terraform/laba/backend.tf`:

```hcl
# terraform/laba/backend.tf
terraform {
  backend "s3" {
    bucket = "laba"
    key    = "laba/terraform.tfstate"
    region = "main"

    endpoints = {
      s3 = "https://s3-api.personal.org.ua"
    }

    # Credentials via environment variables:
    # AWS_ACCESS_KEY_ID
    # AWS_SECRET_ACCESS_KEY

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}
```

Each environment (e.g. `staging`, `prod`) gets its own `key` (e.g. `staging/terraform.tfstate`) so state never collides.

### Required Runtime Variables (never in files)

| Env variable | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | S3-compatible backend access key |
| `AWS_SECRET_ACCESS_KEY` | S3-compatible backend secret key |
| `TF_VAR_ssh_public_key` | SSH public key injected into every VM via cloud-init (e.g. `export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"`) |

## Cloud-Init Requirements

Every VM must receive all of the following at first boot (see `terraform/laba/cloud-init/user-data.yaml.tftpl`).

### 1. Hostname, admin user + SSH key

```yaml
#cloud-config
hostname: ${hostname}
fqdn: ${hostname}.${domain_name}
manage_etc_hosts: true

ssh_pwauth: false
disable_root: true

users:
  - name: ${admin_user}
    groups: [sudo]
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - ${ssh_public_key}
```

- Hostname, admin username and SSH public key supplied via `templatefile()` variables
- `ssh_pwauth: false` and `disable_root: true` are mandatory
- No passwords stored in any file
- If a VM was provisioned before `TF_VAR_ssh_public_key` was exported, `ssh_authorized_keys` renders empty and SSH will fail with "Permission denied (publickey)" — re-export the var and re-apply to fix.
- `fqdn` is `<hostname>.${var.domain_name}` (e.g. `freeipa.personal.internal`) — `domain_name` is a root variable set in `config.tfvars` (currently `"personal.internal"`), shared with the DNS search domain below.

### 2. Hostname + static networking

```yaml
# cloud-init/network-config.yaml.tftpl (cloud-init v2 format)
version: 2
ethernets:
  ${network_interface}:           # e.g. enp1s0 — variable, not hardcoded
    dhcp4: false
    addresses:
      - ${ip_address}              # CIDR form, e.g. 192.168.0.10/16
    routes:
      - to: default
        via: ${gateway}
    nameservers:
      addresses: ${jsonencode(dns)}
      search: ${jsonencode([domain_name])}   # e.g. ["personal.internal"]
```

### 3. Base package install

Mandatory packages on every VM:

```yaml
packages:
  - qemu-guest-agent    # required for libvirt introspection
  - rng-tools           # rngd feeds /dev/urandom from the virtio-rng device — avoids long crng init delays
  - nftables
  - curl
  - ca-certificates
  - git
package_update: true
package_upgrade: false  # pin upgrades to maintenance windows
```

`rng-tools` only helps if the domain also has a `virtio` `rngs` device — see [libvirt_domain Schema Notes](#libvirt_domain-schema-notes-09x-provider).

### 4. Firewall (nftables)

Apply a restrictive default policy via `runcmd`:

```yaml
runcmd:
  - systemctl enable --now qemu-guest-agent
  - systemctl enable --now rngd
  - |
    nft -f - <<'NFTEOF'
    table inet filter {
      chain input {
        type filter hook input priority 0; policy drop;
        iif "lo" accept
        ct state established,related accept
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept
        tcp dport 22 accept
        log prefix "nft-drop: " drop
      }
      chain forward { type filter hook forward priority 0; policy drop; }
      chain output  { type filter hook output  priority 0; policy accept; }
    }
    NFTEOF
  - nft list ruleset > /etc/nftables.conf
  - systemctl enable --now nftables
```

Currently SSH (`tcp dport 22`) is open to any source. Restrict to a management CIDR via a `templatefile()` variable before exposing any VM beyond the trusted LAN.

### 5. Fedora cloud-init differences (`user-data-fedora.yaml.tftpl`)

VMs with `os = "fedora"` (currently only `freeipa`) use a separate user-data template, `cloud-init/user-data-fedora.yaml.tftpl`, instead of `user-data.yaml.tftpl`. Differences from the Ubuntu template:

- **Admin user group**: `groups: [wheel]` (Fedora's sudo group), not `[sudo]`.
- **Packages**: `qemu-guest-agent`, `rng-tools`, `curl`, `ca-certificates`, `git`, and conditionally `lvm2` — same set as Ubuntu minus `nftables` (Fedora uses firewalld instead).
- **Firewall**: `firewalld` (Fedora's default), not raw `nftables`. `runcmd` enables firewalld, sets the default zone to `public`, and opens only `ssh`. This baseline is intentionally minimal — `ansible-freeipa`'s `ipaserver` role (with `ipaserver_setup_firewalld: true`, the role default) ADDS FreeIPA's required ports (LDAP/LDAPS, Kerberos, DNS, HTTP/HTTPS, NTP) on top of this baseline during the Ansible run (see [FreeIPA Ansible Project](#freeipa-ansible-project-ansiblefreeipa-ansible)). Verify the active zone with `firewall-cmd --get-active-zones` if firewalld behavior seems unexpected — some Fedora Cloud variants default to a `FedoraServer` zone rather than `public`.
- **SELinux**: left at its Fedora-default `Enforcing` mode — not disabled. ansible-freeipa's `ipaserver` role manages the SELinux contexts/booleans FreeIPA needs.
- **`/etc/hosts` / FQDN resolution**: `manage_etc_hosts: false` (cloud-init's default `/etc/hosts` management writes a `127.0.1.1 <fqdn>` entry, which breaks `ipa-server-install`'s requirement that the FQDN resolve to the VM's real static IP). Instead, `write_files` renders a complete static `/etc/hosts` with `${ip_address_no_cidr} <fqdn> <hostname>` (the IP, stripped of its `/<cidr>` suffix via `split("/", each.value.ip_address)[0]` in `main.tf`).
- **Data disk LVM provisioning** (`pvcreate`/`vgcreate`/`lvcreate`/`mkfs`/fstab/mount `runcmd` block): identical to the Ubuntu template, copied verbatim — these are distro-agnostic LVM2/util-linux commands.
- `network-config.yaml.tftpl` is **shared, unchanged** — see [Per-VM Operating System (`os`)](#per-vm-operating-system-os) below.

## Per-VM Operating System (`os`)

Each entry in `var.vms` (`terraform/laba/config.tfvars`) has an `os` field:

```hcl
vms = {
  "freeipa" = {
    # ...
    os = "fedora"   # default is "ubuntu" if omitted
  }
}
```

- `os = optional(string, "ubuntu")`, validated to be one of `"ubuntu"` or `"fedora"`.
- `os = "ubuntu"` (default): the per-VM overlay's `base_volume_path` points at `module.libvirt_volume_base` (Ubuntu 24.04 Noble, `source_url` hardcoded to the evergreen `cloud-images.ubuntu.com/noble/current/` URL), and cloud-init renders `cloud-init/user-data.yaml.tftpl` (netplan/nftables/`sudo` group).
- `os = "fedora"`: the overlay's `base_volume_path` points at `module.libvirt_volume_base_fedora` (Fedora Cloud Base, `source_url` = `var.fedora_cloud_image_url`), and cloud-init renders `cloud-init/user-data-fedora.yaml.tftpl` (NetworkManager/firewalld/SELinux/`wheel` group — see above).
- `network-config.yaml.tftpl` (cloud-init v2 network-config schema) is **shared/reused unchanged** for both OSes — the schema is renderer-agnostic across netplan (Ubuntu) and NetworkManager/sysconfig (Fedora).
- Currently only the `freeipa` VM uses `os = "fedora"` (required because ansible-freeipa's `ipaserver` role does not support Ubuntu).

### `fedora_cloud_image_url`

Set in `config.tfvars`. Unlike Ubuntu's evergreen `noble/current/` URL, Fedora has no equivalent "always current stable" path — `fedora_cloud_image_url` must be a versioned URL to a specific Fedora release's "Generic" Cloud Base x86_64 qcow2 image. **Before every `terraform apply` that (re)creates the Fedora base volume**, check https://fedoraproject.org/cloud/download for the current stable (non-Beta, non-Rawhide) release and update this URL if a newer release has superseded it. Never point this at a Beta or Rawhide build (violates the "latest LTS/stable only" rule above).

## Cloud-Init Template Rendering

Use the `templatefile()` built-in function. **Do not use** the deprecated `data "template_file"` data source.

```hcl
# modules/libvirt_cloudinit_disk/main.tf
resource "libvirt_cloudinit_disk" "cloudinit" {
  name           = "${var.project_name}-${var.vm_name}-cloudinit.iso"
  meta_data      = "instance-id: ${var.vm_name}\nlocal-hostname: ${var.vm_name}\n"
  user_data      = var.user_data
  network_config = var.network_config
}
```

`user_data` / `network_config` are rendered by the root module with `templatefile(...)` and passed in as plain strings. The 0.9.8 provider's `libvirt_cloudinit_disk` resource has no `pool` attribute and requires `meta_data`.

## libvirt_domain Schema Notes (0.9.x provider)

The plugin-framework rewrite changed several attributes from the 0.8.x docs/examples. These are required for VMs to boot correctly on this host (q35 + UEFI/SeaBIOS via OVMF-less default):

- **`running = true` and `autostart = true`** — set on every domain. Without `running = true`, the 0.9.x provider creates the domain in shut-off state (defined but not started) after `terraform apply`; `autostart = true` also starts it automatically on host (`libvirtd`) boot.

- **`os`**: flat attributes, not a nested `type` sub-object:
  ```hcl
  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }
  ```
  Omitting this fails with "an os <type> must be specified".

- **`features.acpi` / `features.apic`** — **required**:
  ```hcl
  features = {
    acpi = true   # bool
    apic = {}     # object (presence flag)
  }
  ```
  Without ACPI, the RSDP table is missing, ACPI is disabled in the guest kernel, and every virtio-pci device behind a q35 PCIe root port (disk, net, RNG) fails its D3cold→D0 power transition and falls back to legacy drivers absent from the initramfs. Symptom: `ALERT! LABEL=cloudimg-rootfs does not exist. Dropping to a shell!` even though the disk is attached correctly.

- **`memory_unit = "MiB"`** — **required** alongside `memory`. Without it, `memory` is interpreted in KiB (`memory = 6194` ≈ 6 MB), and GRUB fails with "Out of memory, you need to load kernel first!".

- **Per-device boot order**: set `boot = { order = N }` on each `disks[]` entry (root disk `vda` = 1, cloud-init `cdrom` = 2). Do **not** also set `os.boot_devices` — libvirt rejects domains that mix per-device boot order with the global boot device list.

- **Console / graphics devices** — required or libvirt reports "Graphical console not configured for guest":
  ```hcl
  devices = {
    serials = [{
      source = { vc = true }          # vc is a bool presence flag, not an object
      target = { port = 0 }
      log = {
        file   = "/var/log/libvirt/qemu/${var.project_name}-${var.vm_name}-console.log"
        append = "on"
      }
    }]
    consoles = [{
      source = { vc = true }
      target = { type = "serial", port = 0 }
    }]
    graphics = [{
      vnc = { auto_port = true, listen = "127.0.0.1" }   # local-only emergency access via virt-manager
    }]
  }
  ```
  The `serials[0].log.file` path persists the full boot console output to the host, surviving terminal scrollback — useful for diagnosing early-boot failures: `tail -f /var/log/libvirt/qemu/<project>-<vm>-console.log`.

- **virtio RNG device** — pairs with `rng-tools`/`rngd` in cloud-init to eliminate `crng init done` boot delays (otherwise 30s–160s+):
  ```hcl
  rngs = [{
    model   = "virtio"
    backend = { random = "/dev/urandom" }   # random is a plain string path, not an object
  }]
  ```

- `xhci_hcd` "Could not allocate xHCI MSI interrupt" / `-110` errors in the boot log are cosmetic — the USB3 controller is present but unused (no USB devices attached). Safe to ignore.

## Extra Data Disks (`data_disks`)

VMs that need additional storage (e.g. GitLab) can declare extra virtio data disks per-VM in `terraform/laba/config.tfvars`. Each entry is formatted and mounted automatically by cloud-init:

```hcl
vms = {
  "gitlab" = {
    vcpu         = 4
    memory       = 6194
    ip_address   = "192.168.0.11/16"
    gateway      = "192.168.0.1"
    dns          = ["1.1.1.1", "8.8.8.8"]
    disk_size_gb = 60
    data_disks = [
      { size_gb = 200, mount_point = "/var/opt/gitlab", fs_type = "ext4" }  # → vdb
      # { size_gb = 50, mount_point = "/data2", fs_type = "ext4" }         # → vdc
    ]
  }
}
```

- `data_disks` is `optional(list(object({ size_gb, format = optional(bool, true), mount_point = optional(string, null), fs_type = optional("ext4") })), [])` — VMs that don't need extra disks omit it (defaults to none).
- **`format = false`** attaches the disk (`vdb`, `vdc`, ...) without any cloud-init provisioning — for guests that manage the raw block device themselves (Ceph OSD, ZFS, a database wanting raw I/O). `mount_point` is unused in this case. A variable validation on `vms` enforces that any entry with `format = true` (the default) must set `mount_point`.
- Each entry becomes its own `libvirt_volume` instance (named `<project>-<vm>-data<index>`), created via `local.vm_data_disks` (flattened `{vm => [data_disks]}` → `{"<vm>-data<index>" => {capacity = size_gb}}`) in `terraform/laba/main.tf`.
- The `libvirt_domain` module receives the resulting volume names as `data_volume_names` (ordered list) and attaches them as `vdb`, `vdc`, ... `vdz` (via `substr("bcdefghijklmnopqrstuvwxyz", idx, 1)`), all `virtio`/`qcow2`, with no boot order set (data disks aren't bootable).
- **Each data disk is its own LVM PV+VG+LV, set up by cloud-init.** `local.vm_data_disk_mounts` in `terraform/laba/main.tf` computes the matching `/dev/vdb`, `/dev/vdc`, ... device path per entry (same `idx` ordering as `data_volume_names`) and passes `{device, mount_point, fs_type, label}` (`label` = `data0`, `data1`, ...) into `user-data.yaml.tftpl`. For each entry, `runcmd` renders an idempotent block:
  ```bash
  if ! pvs /dev/vdb >/dev/null 2>&1; then
    pvcreate /dev/vdb
    vgcreate vg_data0 /dev/vdb
    lvcreate -l 100%FREE -n lv_data0 vg_data0
    mkfs.ext4 /dev/vg_data0/lv_data0
  fi
  mkdir -p /opt/gitlab
  if ! grep -q "/dev/vg_data0/lv_data0" /etc/fstab; then
    echo "/dev/vg_data0/lv_data0  /opt/gitlab  ext4  defaults,nofail  0  2" >> /etc/fstab
  fi
  mount /opt/gitlab
  ```
  - `pvs /dev/vdb` gates the create/format step — safe to re-apply/reboot without reformatting.
  - VG/LV naming (`vg_dataN`/`lv_dataN`) gives a stable mount device independent of `/dev/vdX` ordering, and each LV can later be grown with `lvextend` + `resize2fs` (or `xfs_growfs`) without repartitioning.
  - The `lvm2` package is added to `packages` only when a VM has `data_disks`.
  - cloud-init's `mounts` module isn't used for data disks (it runs *before* `runcmd`, so the LV wouldn't exist yet) — the `/etc/fstab` entry and mount are done manually in `runcmd`.
- This whole `runcmd` block (and the `lvm2` package) is omitted entirely when a VM has no `data_disks`.

## FreeIPA Ansible Project (`ansible/freeipa-ansible/`)

A separate Ansible project (not invoked by Terraform) configures the `freeipa` VM (provisioned by `terraform/laba/` with `os = "fedora"`, static IP `192.168.0.10`, FQDN `freeipa.personal.internal`) as a **standalone FreeIPA server**: LDAP directory, Kerberos KDC (`PERSONAL.INTERNAL` realm), integrated DNS (serving `personal.internal`, which all other `laba` VMs already point their `dns` at), CA, and ACME (enabled post-install via `ipa-acme-manage enable`).

Uses the upstream [`freeipa.ansible_freeipa`](https://github.com/freeipa/ansible-freeipa) collection's `ipaserver` role — chosen specifically because this role does not support Ubuntu (only `ipaclient` does), which is why the `freeipa` VM runs Fedora (`os = "fedora"`) while every other VM in this repo runs Ubuntu.

### Relationship to `terraform apply`

These are **two independent steps, run in sequence, not coupled**:

1. `terraform apply` (from `terraform/laba/`) provisions the `freeipa` VM: Fedora OS, static networking, firewalld baseline (SSH-only), SSH access as `ops`.
2. `ansible-playbook -i inventory/hosts.ini playbook.yml --ask-vault-pass` (from `ansible/freeipa-ansible/`) installs and configures FreeIPA on top of the already-running VM.

Re-running step 2 (e.g. after a FreeIPA config change) does NOT require re-running step 1, and vice versa — `terraform apply` for other VMs/changes does not affect or require re-running the Ansible playbook.

See `ansible/freeipa-ansible/README.md` for full setup (vault secrets, collection install, host-key verification) and post-install verification steps.

## Security Rules

1. **No secrets in code.** Passwords, SSH keys, and tokens go in environment variables or `TF_VAR_*` — never in `.tf`, `.yaml`, or `.tfvars` files.
2. **No root SSH.** Cloud-init must set `disable_root: true` and `ssh_pwauth: false` on every VM.
3. **`.gitignore` must exclude:** `.terraform/`, `terraform.tfstate*`, `bin/` (provider lock file `.terraform.lock.hcl` and `config.tfvars` ARE committed — they contain no secrets).
4. **`.terraform.lock.hcl` is committed.** Always include it in git.
5. **Provider version uses a floor constraint (`>= 0.9.8`)**, with the exact resolved version pinned via `.terraform.lock.hcl`. Update intentionally with `terraform init -upgrade`, and re-run `terraform init -upgrade` + commit the updated lock file after bumping the floor.
6. **Bridge name is a variable.** Never hardcode `nm-bridge-dev` (or any interface name) inside module resource blocks — use `var.bridge_name`.
7. **`memory` and `vcpu` are `number` type**, not `string`.
8. **State backend must support locking.** Never `terraform apply` with a local state file outside of a single-operator dev workflow.
9. **Module blocks require quoted labels**: `module "libvirt_cloudinit_disk"`, not `module libvirt_cloudinit_disk`.

## Known Issues — Fix Before Production

- [ ] `modules/libvirt_volume/main.tf`: neither the Ubuntu Noble image URL nor `fedora_cloud_image_url` have a checksum (`source_hash`/similar) — add SHA256 verification of downloaded base images.
- [ ] nftables `tcp dport 22 accept` is open to any source — restrict to a management CIDR via a templatefile variable.
- [ ] Only the `laba` environment exists — `staging`/`prod` root modules (with their own `backend.tf` state key) are not yet created.

## Host Prerequisites

These must exist on the Fedora Server before `terraform apply`:

- `libvirtd` running: `systemctl enable --now libvirtd`
- Bridge interface (e.g. `nm-bridge-dev`) created via NetworkManager and connected to the physical NIC
- Storage directory exists and `qemu` user has write access: `chown qemu:qemu /data/libvirt_pool`
- Firewalld zone permits libvirt: `firewall-cmd --permanent --zone=trusted --add-interface=virbr0 --add-interface=nm-bridge-dev`
- Terraform binary present at `bin/terraform` or on `$PATH`

## Common Commands

```bash
# All commands run from terraform/laba/

# First-time init (or after provider changes) — requires S3 backend credentials
AWS_ACCESS_KEY_ID=<key> AWS_SECRET_ACCESS_KEY=<secret> terraform init

# Validate and format
terraform validate
terraform fmt -recursive ..

# Plan
TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" terraform plan -var-file=config.tfvars

# Apply
TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" terraform apply -var-file=config.tfvars

# Destroy
TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" terraform destroy -var-file=config.tfvars

# Tail full boot console log for a VM (host-side)
tail -f /var/log/libvirt/qemu/laba-freeipa-console.log
```

## Variable Conventions

- All variables must have `type` and `description`
- No `default = ""` for required values — omit `default` entirely to force explicit supply
- Sensitive variables (keys, tokens) use `sensitive = true`
- Numeric variables (`memory`, `vcpu`) use `type = number`
- Collections use `type = list(string)` or `type = map(string)` as appropriate
- Per-VM optional settings (e.g. `disk_size_gb`, `data_disks_gb`, `network_interface`) use `optional(type, default)` inside the `vms` object type
