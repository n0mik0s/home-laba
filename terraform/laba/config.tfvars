project_name = "laba"
bridge_name  = "nm-bridge-dev"
domain_name  = "personal.internal"
pool_path    = "/data/libvirt_pool"
admin_user   = "ops"

# Fedora Cloud Base "Generic" x86_64 qcow2 — used for os = "fedora" VMs (freeipa).
# Fedora has no evergreen "/current/" URL like Ubuntu's noble/current/. Before
# `terraform apply`, verify the current STABLE (non-Beta) release at
# https://fedoraproject.org/cloud/download and update this URL if a newer
# Fedora release has superseded it.
fedora_cloud_image_url = "https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2"

# ssh_public_key — supply via environment:
#   export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"

vms = {
  "freeipa" = {
    vcpu              = 4
    memory            = 6144
    ip_address        = "192.168.0.10/16"
    gateway           = "192.168.0.1"
    dns               = ["1.1.1.1", "8.8.8.8"]
    os                = "fedora"
    network_interface = "enp1s0"
    disk_size_gb      = 100
  }

  "k3s-rancher" = {
    vcpu              = 4
    memory            = 6144
    ip_address        = "192.168.0.11/16"
    gateway           = "192.168.0.1"
    dns               = ["192.168.0.10"]
    network_interface = "enp1s0"
    disk_size_gb      = 30
    data_disks = [
      { size_gb = 50, mount_point = "/var", fs_type = "ext4" }
    ]
  }

  "postgresql-db" = {
    vcpu              = 4
    memory            = 8192
    ip_address        = "192.168.0.12/16"
    gateway           = "192.168.0.1"
    dns               = ["192.168.0.10"]
    network_interface = "enp1s0"
    disk_size_gb      = 30
    data_disks = [
      { size_gb = 100, mount_point = "/opt/db", fs_type = "ext4" }
    ]
  }

  "k8s-master-1" = {
    vcpu              = 4
    memory            = 6144
    ip_address        = "192.168.0.21/16"
    gateway           = "192.168.0.1"
    dns               = ["192.168.0.10"]
    network_interface = "enp1s0"
    disk_size_gb      = 30
    data_disks = [
      { size_gb = 50, mount_point = "/var", fs_type = "ext4" }
    ]
  }

  "k8s-master-2" = {
    vcpu              = 4
    memory            = 6144
    ip_address        = "192.168.0.22/16"
    gateway           = "192.168.0.1"
    dns               = ["192.168.0.10"]
    network_interface = "enp1s0"
    disk_size_gb      = 30
    data_disks = [
      { size_gb = 50, mount_point = "/var", fs_type = "ext4" }
    ]
  }

  "k8s-master-3" = {
    vcpu              = 4
    memory            = 6144
    ip_address        = "192.168.0.23/16"
    gateway           = "192.168.0.1"
    dns               = ["192.168.0.10"]
    network_interface = "enp1s0"
    disk_size_gb      = 30
    data_disks = [
      { size_gb = 50, mount_point = "/var", fs_type = "ext4" }
    ]
  }

  "k8s-worker-1" = {
    vcpu              = 8
    memory            = 32768
    ip_address        = "192.168.0.31/16"
    gateway           = "192.168.0.1"
    dns               = ["192.168.0.10"]
    network_interface = "enp1s0"
    disk_size_gb      = 30
    data_disks = [
      { size_gb = 50, mount_point = "/var", fs_type = "ext4" },
      { size_gb = 200, format = false }
    ]
  }

  "k8s-worker-2" = {
    vcpu              = 8
    memory            = 32768
    ip_address        = "192.168.0.32/16"
    gateway           = "192.168.0.1"
    dns               = ["192.168.0.10"]
    network_interface = "enp1s0"
    disk_size_gb      = 30
    data_disks = [
      { size_gb = 50, mount_point = "/var", fs_type = "ext4" },
      { size_gb = 200, format = false }
    ]
  }

  "k8s-worker-3" = {
    vcpu              = 8
    memory            = 32768
    ip_address        = "192.168.0.33/16"
    gateway           = "192.168.0.1"
    dns               = ["192.168.0.10"]
    network_interface = "enp1s0"
    disk_size_gb      = 30
    data_disks = [
      { size_gb = 50, mount_point = "/var", fs_type = "ext4" },
      { size_gb = 200, format = false }
    ]
  }
}