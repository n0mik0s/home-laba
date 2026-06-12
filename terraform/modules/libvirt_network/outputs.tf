output "network_id" {
  value       = libvirt_network.network.id
  description = "libvirt network ID"
}

output "network_name" {
  value       = libvirt_network.network.name
  description = "libvirt network name"
}
