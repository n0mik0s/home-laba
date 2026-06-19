#!/usr/bin/env python3
"""External dynamic inventory script.

Derives the `ipaserver` host (and any allow-listed `ipaclients` hosts) from
terraform/laba's `vm_ips` output instead of a hand-maintained static IP list,
so the IP here can never drift from terraform/laba/config.tfvars.

Stdlib-only on purpose: Ansible's `script` inventory plugin executes this
file directly via its own shebang, not via whatever interpreter launched
ansible-playbook, so it must not depend on the uv-managed venv being active.

Requires AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY in the environment (same
ones Terraform's S3 backend uses) to read remote state — see
confidential/.env and README.md.
"""
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
TF_DIR = REPO_ROOT / "terraform" / "laba"
ALLOWLIST_FILE = Path(__file__).resolve().parent / "ipaclients_allowlist.json"

DOMAIN_NAME = "personal.internal"  # matches group_vars/ipaserver.yml ipaserver_domain
ADMIN_USER = "ops"  # matches the cloud-init admin user / former ansible.cfg remote_user
IPASERVER_VM_KEY = "freeipa"  # matches the vms key in terraform/laba/config.tfvars


def terraform_binary() -> str:
    pinned = REPO_ROOT / "bin" / "terraform"
    return str(pinned) if pinned.exists() else "terraform"


def terraform_vm_ips() -> dict:
    try:
        result = subprocess.run(
            [terraform_binary(), f"-chdir={TF_DIR}", "output", "-json", "vm_ips"],
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as exc:
        sys.stderr.write(
            "terraform output failed — is the S3 backend reachable and are "
            "AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY exported? "
            "(source confidential/.env)\n"
        )
        sys.stderr.write(exc.stderr)
        sys.exit(1)
    return json.loads(result.stdout)


def allowlisted_clients() -> list:
    if not ALLOWLIST_FILE.exists():
        return []
    return json.loads(ALLOWLIST_FILE.read_text())


def build_inventory() -> dict:
    vm_ips = terraform_vm_ips()
    hostvars = {}
    groups = {"ipaserver": {"hosts": []}, "ipaclients": {"hosts": []}}

    def add_host(group: str, vm_key: str) -> None:
        ip = vm_ips[vm_key].split("/")[0]
        hostname = f"{vm_key}.{DOMAIN_NAME}"
        groups[group]["hosts"].append(hostname)
        hostvars[hostname] = {"ansible_host": ip, "ansible_user": ADMIN_USER}

    if IPASERVER_VM_KEY in vm_ips:
        add_host("ipaserver", IPASERVER_VM_KEY)

    for vm_key in allowlisted_clients():
        if vm_key in vm_ips:
            add_host("ipaclients", vm_key)

    groups["_meta"] = {"hostvars": hostvars}
    return groups


def main() -> None:
    if "--list" in sys.argv:
        print(json.dumps(build_inventory()))
    elif "--host" in sys.argv:
        print(json.dumps({}))  # all vars are already in --list's _meta.hostvars
    else:
        sys.stderr.write(f"Usage: {sys.argv[0]} --list | --host <hostname>\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
