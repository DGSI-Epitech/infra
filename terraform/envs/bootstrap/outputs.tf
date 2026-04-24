output "terraform_token_secret" {
  description = "UUID secret du token root@pam!terraform"
  value       = proxmox_user_token.terraform.value
  sensitive   = true
}
