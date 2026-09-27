variable "subscription_id" {
  description = "Azure subscription ID to deploy into"
  type        = string
}

variable "prefix" {
  description = "Name prefix for every resource"
  type        = string
  default     = "obs2"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "westus3"
}

variable "vm_size" {
  description = "VM size"
  type        = string
  default     = "Standard_D2s_v7"
}

variable "admin_username" {
  description = "Linux admin user on the VM"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key that gets installed on the VM"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "extra_ssh_public_keys" {
  description = "Public keys for the other team members"
  type        = list(string)
  default     = []
}

variable "allowed_source_ips" {
  description = "Permanent list of public IPs allowed to reach SSH, Prometheus and Grafana"
  type        = list(string)
}

variable "extra_allowed_ips" {
  description = "Temporary extra IPs, for example the current Cloud Shell address"
  type        = list(string)
  default     = []
}

variable "repo_url" {
  description = "HTTPS URL of the project Git repo. Empty means skip auto deploy."
  type        = string
  default     = ""
}

variable "grafana_admin_user" {
  description = "Grafana admin username"
  type        = string
  default     = "admin"
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

variable "data_disk_size_gb" {
  description = "Size of the persistent data disk that holds Prometheus and Grafana state. Survives VM replacement."
  type        = number
  default     = 32
}

variable "data_disk_lun" {
  description = "LUN the data disk is attached at. The VM finds it at /dev/disk/azure/scsi1/lun<this>."
  type        = number
  default     = 10
}
