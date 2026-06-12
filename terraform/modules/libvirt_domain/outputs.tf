output "id" {
  value       = libvirt_domain.domain.id
  description = "Domain ID"
}

output "name" {
  value       = libvirt_domain.domain.name
  description = "Domain name"
}
