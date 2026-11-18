variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint, for example https://pve.example.com:8006/"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox VE API token in the form user@realm!tokenid=secret"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification of the Proxmox API (self-signed lab certificates)"
  type        = bool
  default     = false
}

variable "proxmox_ssh_username" {
  description = "SSH user on the Proxmox node, used by the provider to import the cloud image"
  type        = string
  default     = "root"
}

variable "node_name" {
  description = "Proxmox node that hosts the VMs"
  type        = string
}

variable "datastore_id" {
  description = "Datastore for VM disks and the cloud-init drive"
  type        = string
  default     = "local-lvm"
}

variable "image_datastore_id" {
  description = "Datastore (with the iso content type) that stores the downloaded cloud image"
  type        = string
  default     = "local"
}

variable "snippets_datastore_id" {
  description = "Datastore with the snippets content type, for the cloud-init user-data"
  type        = string
  default     = "local"
}

variable "image_url" {
  description = "Alpine Linux 3.23 cloud image (BIOS, cloud-init, NoCloud)"
  type        = string
  default     = "https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/cloud/alpine-3.23.8-x86_64-bios-cloudinit-r0.qcow2"
}

variable "image_file_name" {
  description = "File name for the downloaded image on the Proxmox datastore (.img so it can be imported as a disk)"
  type        = string
  default     = "alpine-3.23.8-x86_64-bios-cloudinit-r0.img"
}

variable "domain" {
  description = "DNS domain of the VMs; inventory names are <name>.<domain>, which the certificates and Kerberos use"
  type        = string
  default     = "example.com"
}

variable "bridge" {
  description = "Network bridge for the VMs"
  type        = string
  default     = "vmbr0"
}

variable "vlan_id" {
  description = "Optional VLAN tag for the VM network interface"
  type        = number
  default     = null
}

variable "gateway" {
  description = "IPv4 default gateway for the VMs"
  type        = string
}

variable "dns_servers" {
  description = "DNS servers the VMs use during provisioning"
  type        = list(string)
  default     = ["9.9.9.9", "1.1.1.1"]
}

variable "vm_username" {
  description = "User created by cloud-init; Ansible connects as this user"
  type        = string
  default     = "alpine"
}

variable "ssh_public_key" {
  description = "SSH public key installed for vm_username"
  type        = string
}

variable "vms" {
  description = "VMs to create. Key is the short host name. group is infra (LDAP + KDC node) or ldap_clients; ipv4_address is in CIDR notation."
  type = map(object({
    group          = optional(string, "infra")
    ldap_server_id = optional(number)
    vm_id          = optional(number)
    ipv4_address   = string
    cores          = optional(number, 1)
    memory_mb      = optional(number, 1024)
    disk_gb        = optional(number, 8)
  }))

  validation {
    condition     = alltrue([for vm in values(var.vms) : contains(["infra", "ldap_clients"], vm.group)])
    error_message = "Each VM needs group = \"infra\" or group = \"ldap_clients\"."
  }
}
