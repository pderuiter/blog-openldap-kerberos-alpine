resource "proxmox_download_file" "alpine_cloud_image" {
  content_type = "iso"
  datastore_id = var.image_datastore_id
  node_name    = var.node_name
  url          = var.image_url
  file_name    = var.image_file_name
  overwrite    = false
}

# The Alpine cloud image ships without Python and sudo; cloud-init installs
# both so Ansible can connect, and sets the host name.
resource "proxmox_virtual_environment_file" "user_data" {
  for_each = var.vms

  content_type = "snippets"
  datastore_id = var.snippets_datastore_id
  node_name    = var.node_name

  source_raw {
    file_name = "${local.project_tag}-${each.key}-user-data.yaml"
    data = templatefile("${path.module}/user-data.yaml.tftpl", {
      hostname       = each.key
      fqdn           = "${each.key}.${var.domain}"
      username       = var.vm_username
      ssh_public_key = var.ssh_public_key
    })
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.vms

  name      = each.key
  node_name = var.node_name
  vm_id     = each.value.vm_id
  tags      = ["blog", local.project_tag, each.value.group]

  agent {
    enabled = false
  }

  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory_mb
  }

  disk {
    datastore_id = var.datastore_id
    file_id      = proxmox_download_file.alpine_cloud_image.id
    interface    = "virtio0"
    size         = each.value.disk_gb
    discard      = "on"
  }

  network_device {
    bridge  = var.bridge
    vlan_id = var.vlan_id
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  initialization {
    datastore_id      = var.datastore_id
    user_data_file_id = proxmox_virtual_environment_file.user_data[each.key].id

    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = each.value.ipv4_address
        gateway = var.gateway
      }
    }
  }
}
