variable "node_name" {}
variable "node_ip" {}
variable "vms" {
  type = map(object({
    vm_id        = number
    cores        = number
    memory       = number
    disk_size    = string
    ip           = string
    mac_address  = string
    is_cp        = bool
    node_type    = string
    zone         = string
    role         = string
    run_on_ssd   = bool
    tags         = list(string)
  }))
}
variable "use_local_iso" {}
variable "is_development" {}
variable "cluster_name" {}
variable "cluster_vip" {}
variable "cluster_endpoint" {}
variable "iso_url" {}
variable "iso_name" {}
variable "install_image" {}
variable "local_iso" {}
variable "talos_path" {}
variable "network_cidr" {}
variable "network_gateway" {}
variable "machine_secrets" {
  type = any
  sensitive = true
}
variable "client_configuration" {
  type = any
}
