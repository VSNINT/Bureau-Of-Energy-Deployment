resource "random_password" "vm_password" {
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
}
