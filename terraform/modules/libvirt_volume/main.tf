resource "libvirt_volume" "volume" {
  name          = "${var.project_name}-${var.vm_name}"
  pool          = var.pool
  capacity      = var.capacity
  capacity_unit = var.capacity != null ? var.capacity_unit : null

  target = {
    format = {
      type = "qcow2"
    }
  }

  create = var.source_url != null ? {
    content = {
      url = var.source_url
    }
  } : null

  backing_store = var.base_volume_path != null ? {
    path = var.base_volume_path
    format = {
      type = "qcow2"
    }
  } : null
}
