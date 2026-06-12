variable "project_name" {
  type        = string
  description = "Project name"
}

variable "bridge_name" {
  type        = string
  description = "Host bridge interface to attach the network to (e.g. nm-bridge-dev)"
}
