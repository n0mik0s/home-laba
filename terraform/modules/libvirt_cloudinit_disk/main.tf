resource "libvirt_cloudinit_disk" "cloudinit" {
  name           = "${var.project_name}-${var.vm_name}-cloudinit.iso"
  meta_data      = "instance-id: ${var.vm_name}\nlocal-hostname: ${var.vm_name}\n"
  user_data      = var.user_data
  network_config = var.network_config
}
