variable "project_name" {
  type        = string
  description = "Project name, used in domain naming"
}

variable "vm_name" {
  type        = string
  description = "VM name segment"
}

variable "memory" {
  type        = number
  description = "Memory in MiB"
}

variable "vcpu" {
  type        = number
  description = "Number of virtual CPUs"
}

variable "pool_name" {
  type        = string
  description = "Storage pool name containing the root volume"
}

variable "volume_name" {
  type        = string
  description = "Root disk volume name within the pool"
}

variable "network_name" {
  type        = string
  description = "libvirt network name to attach the VM to"
}

variable "cloudinit_disk_path" {
  type        = string
  description = "Filesystem path of the cloud-init ISO (from libvirt_cloudinit_disk.path)"
}

variable "data_volume_names" {
  type        = list(string)
  default     = []
  description = "Ordered names of additional data volumes (within pool_name) to attach as extra virtio disks (vdb, vdc, ...)"
}
