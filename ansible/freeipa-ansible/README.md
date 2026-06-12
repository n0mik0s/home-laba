# FreeIPA Ansible Project

Installs and configures a **standalone FreeIPA server** (LDAP directory,
Kerberos KDC, integrated DNS, CA, and ACME) on the `freeipa` VM provisioned by
`terraform/laba/`.

- FQDN: `freeipa.personal.internal`
- Domain: `personal.internal`
- Kerberos realm: `PERSONAL.INTERNAL`
- IP: `192.168.0.10` (static, set via Terraform/cloud-init)
- OS: Fedora Server Cloud Base (`vms.freeipa.os = "fedora"` in
  `terraform/laba/config.tfvars`)

This project is **independent of `terraform apply`**: Terraform provisions the
VM (OS, networking, firewalld baseline, SSH access); this Ansible project then
configures FreeIPA on top of the running VM. Re-run this playbook any time you
need to change FreeIPA configuration — it does not run as part of
`terraform apply`, and `terraform apply` for other VMs does not require
re-running it.

## Prerequisites

1. `terraform apply` has completed successfully for the `freeipa` VM (see the
   root `CLAUDE.md` "Common Commands").
2. The VM is reachable via SSH as the `ops` user (cloud-init's admin user,
   `var.admin_user`) using the key pair behind `TF_VAR_ssh_public_key`.
3. Populate `known_hosts` for the VM **before** running Ansible, so
   `host_key_checking = True` (in `ansible.cfg`) succeeds without prompts:

   ```bash
   ssh-keyscan -H 192.168.0.10 >> ~/.ssh/known_hosts
   ```

   (`ssh-keyscan` against a known, just-provisioned IP on your own LAN is
   preferred over `host_key_checking = False` / `StrictHostKeyChecking=no`,
   which removes MITM protection entirely.)

4. Install the required Ansible collection:

   ```bash
   cd ansible/freeipa-ansible
   ansible-galaxy collection install -r requirements.yml
   ```

## Secrets management (Ansible Vault)

This playbook requires two passwords, supplied via Ansible Vault:

- `ipadm_password` — FreeIPA Directory Manager (LDAP root DN) password.
- `ipaadmin_password` — FreeIPA `admin` Kerberos principal password.

Setup:

```bash
cd ansible/freeipa-ansible
cp group_vars/ipaserver/vault.yml.example group_vars/ipaserver/vault.yml
# Edit group_vars/ipaserver/vault.yml and replace both CHANGE_ME placeholders
# with long, random, unique passphrases (e.g. `openssl rand -base64 32` each).
ansible-vault encrypt group_vars/ipaserver/vault.yml
```

`group_vars/ipaserver/vault.yml` (the encrypted file, with real passwords) is
gitignored — it never leaves your machine. Keep a copy of both the encrypted
file and the vault password somewhere durable (password manager), since
`ipadm_password` is needed for FreeIPA disaster recovery.

## Running the playbook

```bash
cd ansible/freeipa-ansible
ansible-playbook -i inventory/hosts.ini playbook.yml --ask-vault-pass
```

(Or `--vault-password-file <path>` if you store the vault password in a file
— that file must also never be committed; it matches the existing
`.gitignore` pattern `.vault_pass*`.)

First run takes several minutes — `ipa-server-install` configures 389-ds,
the Kerberos KDC, BIND/named, httpd, and the Dogtag CA/PKI.

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

## Next steps (not covered by this playbook)

- HBAC rules: `ipaserver_no_hbac_allow: true` means no host/user can
  authenticate to any enrolled client by default. Before enrolling other
  hosts (`k3s-rancher`, `k8s-*`, etc.) as IPA clients via `ipaclient`, add
  appropriate HBAC rules for the services/users that need access.
- Other VMs in `config.tfvars` already have `dns = ["192.168.0.10"]` and will
  use this server for DNS resolution once it's up — no further DNS changes
  needed on those VMs.
