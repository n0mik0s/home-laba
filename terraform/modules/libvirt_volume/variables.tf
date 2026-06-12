variable "project_name" {
  type        = string
  description = "Project name, used in volume naming"
}

variable "vm_name" {
  type        = string
  description = "VM or image name segment (e.g. 'ubuntu-noble-base' or 'web01')"
}

variable "pool" {
  type        = string
  description = "Storage pool name"
}

variable "source_url" {
  type        = string
  default     = null
  description = "Remote URL to download the base image from. Mutually exclusive with base_volume_path."
}

variable "base_volume_path" {
  type        = string
  default     = null
  description = "Filesystem path of the base volume to create a qcow2 overlay on. Mutually exclusive with source_url."
}

variable "capacity" {
  type        = number
  default     = null
  description = "Disk size. Unit set by capacity_unit. Only meaningful on overlay volumes; ignored for base images."
}

variable "capacity_unit" {
  type        = string
  default     = "GiB"
  description = "Unit for capacity: bytes, KiB, MiB, GiB, TiB"
}
