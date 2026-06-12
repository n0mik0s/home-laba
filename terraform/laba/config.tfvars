project_name = "laba"
bridge_name  = "nm-bridge-dev"
domain_name  = "personal.internal"
pool_path    = "/data/libvirt_pool"
admin_user   = "ops"

# ssh_public_key — supply via environment:
#   export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"

vms = {
  "freeipa" = {
    vcpu              = 4
    memory            = 6194
    ip_address        = "192.168.0.10/16"
    gateway           = "192.168.0.1"
    dns               = ["1.1.1.1", "8.8.8.8"]
    network_interface = "enp1s0"
    disk_size_gb      = 30
    data_disks = [
      { size_gb = 50, mount_point = "/var", fs_type = "ext4" }
    ]
  }

  "k3s-rancher" = {
    vcpu              = 4
    memory            = 6194
    ip_address        = "192.168.0.11/16"
    gateway           = "192.168.0.1"
    dns               = ["192.168.0.10"]
    network_interface = "enp1s0"
    disk_size_gb      = 30
    data_disks = [
      { size_gb = 50, mount_point = "/var", fs_type = "ext4" }
    ]
  }

  "k8s-master-1" = {
    vcpu              = 4
    memory            = 6194
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
    memory            = 6194
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
    memory            = 6194
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
    memory            = 16384
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
    memory            = 16384
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
    memory            = 16384
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