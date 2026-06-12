output "id" {
  value       = libvirt_volume.volume.id
  description = "Volume ID"
}

output "name" {
  value       = libvirt_volume.volume.name
  description = "Volume name"
}

output "path" {
  value       = libvirt_volume.volume.path
  description = "Filesystem path of the volume (used as backing_store.path for overlays)"
}
