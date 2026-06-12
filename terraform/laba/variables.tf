variable "project_name" {
  type        = string
  description = "Project name used in all resource names"
}

variable "bridge_name" {
  type        = string
  description = "Host bridge interface name (must exist on the hypervisor)"
}

variable "domain_name" {
  type        = string
  description = "DNS domain suffix appended to each VM's hostname to form its FQDN, and used as the DNS search domain in network-config"
}

variable "pool_path" {
  type        = string
  description = "Hypervisor filesystem base path for the storage pool"
}

variable "admin_user" {
  type        = string
  description = "Non-root sudo user created on every VM by cloud-init"
}

variable "ssh_public_key" {
  type        = string
  sensitive   = true
  description = "SSH public key injected into every VM. Supply via TF_VAR_ssh_public_key."
}

variable "vms" {
  type = map(object({
    vcpu              = number
    memory            = number
    ip_address        = string
    gateway           = string
    dns               = list(string)
    network_interface = optional(string, "enp1s0")
    disk_size_gb      = optional(number, 20)
    data_disks = optional(list(object({
      size_gb     = number
      format      = optional(bool, true)
      mount_point = optional(string, null)
      fs_type     = optional(string, "ext4")
    })), [])
  }))
  description = "Map of VM name to VM configuration. data_disks is an ordered list of extra data disks; each entry becomes an additional virtio disk (vdb, vdc, ...). When format = true (default), cloud-init creates an LVM PV/VG/LV on it, formats with fs_type, and mounts at mount_point. When format = false, the disk is attached but left untouched for the guest to manage."

  validation {
    condition = alltrue([
      for vm in var.vms : alltrue([
        for disk in vm.data_disks : !disk.format || disk.mount_point != null
      ])
    ])
    error_message = "Each data_disks entry with format = true (the default) must set mount_point."
  }
}
