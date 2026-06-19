# FreeIPA Ansible Project

Installs and manages a **standalone FreeIPA server** (LDAP directory,
Kerberos KDC, integrated DNS, CA, ACME) on the `freeipa` VM provisioned by
`terraform/laba/`, plus day-2 lifecycle: declarative identity (users,
groups, HBAC), IPA client enrollment, and backup/restore.

- FQDN: `freeipa.personal.internal`
- Domain: `personal.internal`
- Kerberos realm: `PERSONAL.INTERNAL`
- IP: `192.168.0.10` (static, set via Terraform/cloud-init — read dynamically
  from Terraform state, see [Inventory](#inventory) below)
- OS: Fedora Server Cloud Base (`vms.freeipa.os = "fedora"` in
  `terraform/laba/config.tfvars`)

This project is **independent of `terraform apply`**: Terraform provisions the
VM (OS, networking, firewalld baseline, SSH access); this Ansible project then
configures FreeIPA on top of the running VM. Re-run these playbooks any time
you need to change FreeIPA configuration — they don't run as part of
`terraform apply`, and `terraform apply` for other VMs doesn't require
re-running them.

## Toolchain

| Tool | Role |
|---|---|
| [uv](https://docs.astral.sh/uv/) | Pins and runs the control-node Python toolchain (`ansible-core`, `ansible-lint`, `yamllint`, `boto3`/`botocore`, `python-freeipa`) — see `pyproject.toml` / `uv.lock`. |
| [sops](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age) | Encrypts secrets at rest in git. No `ansible-vault`. |
| [freeipa.ansible_freeipa](https://github.com/freeipa/ansible-freeipa) | `ipaserver`, `ipaclient` roles and `ipauser`/`ipagroup`/`ipahbacrule` modules. |
| [community.sops](https://github.com/ansible-collections/community.sops) | Transparently decrypts `*.sops.yaml` group_vars at load time. |
| [amazon.aws](https://github.com/ansible-collections/amazon.aws) | `s3_object`/`s3_object_info` — backup/restore to the same S3-compatible bucket Terraform uses for state. |

All commands below run from `ansible/freeipa-ansible/`, with
`confidential/.env` sourced first (repo root):

```bash
source ../../confidential/.env
```

### A note on `group_vars/` and the `playbooks/` symlink

Ansible resolves `group_vars/`/`host_vars/` relative to **the directory
containing the playbook being run**, not the project root. Since every
playbook here lives in `playbooks/`, `playbooks/group_vars` is a symlink to
`../group_vars` — without it, none of `group_vars/` would ever be loaded
and every `ipaserver_*`/`ipa_*` variable would silently come back undefined.
This is a real, easy-to-hit Ansible gotcha (confirmed by testing), not
defensive boilerplate — don't delete the symlink.

The other Ansible gotcha baked into this layout: a group **cannot** have
both `group_vars/<name>.yml` (a file) and `group_vars/<name>/` (a
directory) — Ansible silently loads only one and drops the other with no
warning. That's why the `ipaserver` group's non-secret config lives at
`group_vars/ipaserver/config.yml` (inside the directory, alongside
`secrets.sops.yaml`) rather than as a sibling `group_vars/ipaserver.yml`.

## Prerequisites

1. `terraform apply` has completed successfully for the `freeipa` VM (see
   the root `CLAUDE.md` "Common Commands" — in `terraform/laba/`).
2. The VM is reachable via SSH as the `ops` user (cloud-init's admin user)
   using the key pair behind `TF_VAR_ssh_public_key`.
3. Populate `known_hosts` for the VM **before** running Ansible, so
   `host_key_checking = True` (in `ansible.cfg`) succeeds without prompts:

   ```bash
   ssh-keyscan -H 192.168.0.10 >> ~/.ssh/known_hosts
   ```

   (`ssh-keyscan` against a known, just-provisioned IP on your own LAN is
   preferred over `host_key_checking = False` / `StrictHostKeyChecking=no`,
   which removes MITM protection entirely.)

4. Pinned CLI binaries (`terraform`, `sops`, `age`/`age-keygen`) exist at the
   repo-root `bin/` (gitignored). Reproduce them any time with:

   ```bash
   ../../scripts/bootstrap-bin.sh        # all three
   ../../scripts/bootstrap-bin.sh sops age   # just these two
   ```

5. Set up the control-node toolchain and install the pinned Ansible
   collections:

   ```bash
   sudo dnf install -y uv   # one-time, if not already installed
   uv sync --group dev
   uv run ansible-galaxy collection install -r requirements.yml
   ```

   From here on, prefix Ansible commands with `uv run` (e.g.
   `uv run ansible-playbook ...`) so they use the pinned toolchain instead of
   whatever's on `$PATH`.

## Inventory

`inventory/terraform.py` is a dynamic inventory script — it runs
`terraform -chdir=../../terraform/laba output -json vm_ips` and builds the
`ipaserver` host from it, so the IP can never drift from
`terraform/laba/config.tfvars`. It needs the same `AWS_ACCESS_KEY_ID` /
`AWS_SECRET_ACCESS_KEY` Terraform uses (sourced from `confidential/.env`) to
read remote state.

`ipaclients` is also derived from Terraform's `vm_ips`, but **only** for VM
keys explicitly listed in `inventory/ipaclients_allowlist.json` (empty `[]`
by default). Adding a VM to `terraform/laba/config.tfvars` never
auto-enrolls it as an IPA client — that's a deliberate, separate opt-in:

```bash
# inventory/ipaclients_allowlist.json
["gitlab", "k3s-master-1"]
```

Sanity-check the inventory any time with:

```bash
uv run ansible-inventory -i inventory/terraform.py --list
```

## Secrets (sops + age)

Three age-encrypted files (`.sops.yaml` lists which path gets which age
recipient — currently one operator key):

| File | Contains | Scope |
|---|---|---|
| `group_vars/ipaserver/secrets.sops.yaml` | `ipadm_password` (Directory Manager) | `ipaserver` group only |
| `group_vars/all/secrets.sops.yaml` | `ipaadmin_principal`, `ipaadmin_password` | All groups (`ipaserver` install + `ipaclients` enrollment both need it) |
| `group_vars/all/identity.sops.yaml` | `ipa_groups` / `ipa_users` / `ipa_hbac_rules` (contains PII) | All groups, consumed by `playbooks/manage-identity.yml` |

All three encrypted files **are committed** — that's the point of sops. Only
`confidential/sops/age-keys.txt` (the private key) must never be committed.

### Step-by-step: encrypting the three files

**Step 0 — one-time age key (already done for this repo).** A key pair
exists at `confidential/sops/age-keys.txt` (private, gitignored) with public
key `age1ne5qwpqntg3m60qugynrqrjufxdajkxqt368rln4kdat6k5mz5mq9xnfzw` (listed
in `.sops.yaml`, safe to commit). Skip to Step 1 unless you're rotating keys
— regenerating is **not** automatic re-encryption, every existing file needs
`sops updatekeys` afterward:

```bash
../../bin/age-keygen -o ../../confidential/sops/age-keys.txt
```

**Step 1 — from `ansible/freeipa-ansible/`, source the env vars.** This
exports `SOPS_AGE_KEY_FILE` (read natively by `sops`) and
`ANSIBLE_SOPS_BINARY` (tells the `community.sops.sops` vars plugin where
`bin/sops` lives):

```bash
source ../../confidential/.env
```

**Step 2 — confirm the pinned binaries and your key are actually there**
(re-run `../../scripts/bootstrap-bin.sh sops age` if either binary check
fails):

```bash
../../bin/sops --version
../../bin/age --version
test -s ../../confidential/sops/age-keys.txt && echo "age key OK"
```

**Step 3 — Directory Manager password** (`ipaserver` group only):

```bash
cp group_vars/ipaserver/secrets.sops.yaml.example group_vars/ipaserver/secrets.sops.yaml
${EDITOR:-vim} group_vars/ipaserver/secrets.sops.yaml   # replace CHANGE_ME with `openssl rand -base64 32`
../../bin/sops -e -i group_vars/ipaserver/secrets.sops.yaml
```

**Step 4 — realm-wide admin password** (needed by both `ipaserver` install
and `ipaclients` enrollment):

```bash
cp group_vars/all/secrets.sops.yaml.example group_vars/all/secrets.sops.yaml
${EDITOR:-vim} group_vars/all/secrets.sops.yaml
../../bin/sops -e -i group_vars/all/secrets.sops.yaml
```

**Step 5 — users/groups/HBAC rules** (the shipped content is examples only
— replace with your real data before running `manage-identity.yml`):

```bash
cp group_vars/all/identity.sops.yaml.example group_vars/all/identity.sops.yaml
${EDITOR:-vim} group_vars/all/identity.sops.yaml
../../bin/sops -e -i group_vars/all/identity.sops.yaml
```

**Step 6 — verify each file actually encrypted** (should print `ENC[` blocks,
never plaintext passwords):

```bash
grep -l "ENC\[" group_vars/ipaserver/secrets.sops.yaml group_vars/all/secrets.sops.yaml group_vars/all/identity.sops.yaml
```

**Step 7 — verify Ansible can decrypt them** (confirms the age key + sops
binary + vars plugin wiring all actually work together, not just that the
file is encrypted):

```bash
uv run ansible -i inventory/terraform.py ipaserver -m debug -a "var=ipaadmin_principal"
```

If that prints `"ipaadmin_principal": "admin"` (or whatever you set), the
pipeline works end-to-end. A failure here usually means
`SOPS_AGE_KEY_FILE`/`ANSIBLE_SOPS_BINARY` aren't exported (re-check Step 1)
or the playbook/command isn't being run from inside
`ansible/freeipa-ansible/` (group_vars resolution is relative to cwd).

**Step 8 — commit.** All three `*.sops.yaml` files are safe to `git add` —
only the `.example` templates and the encrypted files belong in git, never
a decrypted copy.

### Editing an already-encrypted file later

`sops` decrypts to a temp file, opens `$EDITOR`, and re-encrypts on save —
the file on disk is never left in plaintext:

```bash
../../bin/sops group_vars/all/identity.sops.yaml
```

## Running the playbooks

### Install the server

```bash
uv run ansible-playbook playbooks/install.yml
```

First run takes several minutes — `ipa-server-install` configures 389-ds,
the Kerberos KDC, BIND/named, httpd, and the Dogtag CA/PKI. Also enables
ACME (`ipa-acme-manage enable`) as a post-task.

### Apply identity (users, groups, HBAC)

```bash
uv run ansible-playbook playbooks/manage-identity.yml
```

Safe to re-run any time `group_vars/all/identity.sops.yaml` changes —
idempotent, never deletes users/groups/rules absent from that file.
`ipaserver_no_hbac_allow: true` (`group_vars/ipaserver/config.yml`) means nothing
authenticates anywhere until an HBAC rule explicitly allows it.

### Enroll an IPA client

1. Add the VM's Terraform key to `inventory/ipaclients_allowlist.json`.
2. `uv run ansible-inventory -i inventory/terraform.py --list` to confirm it
   now appears under `ipaclients`.
3. `uv run ansible-playbook playbooks/enroll-client.yml`

### Backup

```bash
uv run ansible-playbook playbooks/backup.yml
```

Runs `ipa-backup` on the server, tars the result, uploads it to
`s3://laba/laba/backups/freeipa/` (same bucket/credentials as Terraform
state, different key prefix — `terraform/laba/backend.tf` uses
`laba/terraform.tfstate`), and also keeps a local copy under
`confidential/backups/freeipa/` (gitignored).

### Restore (disaster recovery)

```bash
# Restore the most recent backup
uv run ansible-playbook playbooks/restore.yml -e confirm_restore=true

# Restore a specific backup
uv run ansible-playbook playbooks/restore.yml -e confirm_restore=true \
  -e backup_name=ipa-full-2026-06-01-00-00-00
```

This **overwrites the live server's data** — `confirm_restore=true` is
required or the playbook aborts immediately. Exercise this at least once
against a throwaway VM so the DR path is proven, not just assumed.

## Post-install verification

```bash
# SSH to the freeipa VM
ssh ops@192.168.0.10

# Become root (passwordless sudo)
sudo -i

# Obtain a Kerberos ticket as the IPA admin user (prompts for ipaadmin_password)
kinit admin

# Confirm IPA services are healthy
ipactl status

# Confirm ACME is enabled (should print "ACME is enabled")
ipa-acme-manage status

# Confirm firewalld has FreeIPA's ports open alongside ssh
firewall-cmd --list-services

# Confirm integrated DNS is serving the domain
dig @192.168.0.10 freeipa.personal.internal
```

## Linting

```bash
uv run ansible-lint
uv run yamllint .
```

Local only — no CI pipeline for this project (home-lab scope).

## Next steps / open items

- Other VMs in `config.tfvars` already have `dns = ["192.168.0.10"]` and
  will use this server for DNS resolution once it's up — no further DNS
  changes needed on those VMs.
- `playbooks/enroll-client.yml` is built but `inventory/ipaclients_allowlist.json`
  is empty — nothing is enrolled yet. Populate it host-by-host as those VMs
  (k3s/Rancher nodes, etc.) come online.
- `playbooks/restore.yml` hasn't been exercised against a real server yet —
  do a dry run against a throwaway VM before relying on it.
