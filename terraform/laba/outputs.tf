output "network_id" {
  value       = module.libvirt_network.network_id
  description = "libvirt network ID"
}

output "network_name" {
  value       = module.libvirt_network.network_name
  description = "libvirt network name"
}

output "pool_name" {
  value       = module.libvirt_pool.name
  description = "Storage pool name"
}

output "vm_names" {
  value       = [for k, v in module.libvirt_domain : v.name]
  description = "Provisioned domain names"
}

output "vm_ips" {
  value       = { for k, v in var.vms : k => v.ip_address }
  description = "VM name to IP address"
}
