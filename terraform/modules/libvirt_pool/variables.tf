variable "project_name" {
  type        = string
  description = "Project name, used in the pool resource name"
}

variable "pool_path" {
  type        = string
  description = "Host filesystem base path where the pool directory is created"
}
