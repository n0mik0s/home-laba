output "id" {
  value       = libvirt_cloudinit_disk.cloudinit.id
  description = "Cloud-init disk ID"
}

output "path" {
  value       = libvirt_cloudinit_disk.cloudinit.path
  description = "Filesystem path of the generated cloud-init ISO"
}
