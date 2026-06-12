variable "project_name" {
  type        = string
  description = "Project name, used in the cloud-init ISO name"
}

variable "vm_name" {
  type        = string
  description = "VM name segment, used in the cloud-init ISO name"
}

variable "user_data" {
  type        = string
  description = "Rendered cloud-init user-data content"
}

variable "network_config" {
  type        = string
  description = "Rendered cloud-init network-config content"
}
