output "id" {
  description = "The storage account resource ID."
  value       = azurerm_storage_account.this.id
}

output "name" {
  description = "The storage account name."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Primary blob service endpoint."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_file_endpoint" {
  description = "Primary file service endpoint."
  value       = azurerm_storage_account.this.primary_file_endpoint
}

output "primary_dfs_endpoint" {
  description = "Primary Data Lake Gen2 (dfs) endpoint."
  value       = azurerm_storage_account.this.primary_dfs_endpoint
}

output "primary_web_endpoint" {
  description = "Primary static-website endpoint."
  value       = azurerm_storage_account.this.primary_web_endpoint
}

output "system_assigned_identity_principal_id" {
  description = "Principal ID of the account's system-assigned managed identity."
  value       = azurerm_storage_account.this.identity[0].principal_id
}

output "container_ids" {
  description = "Map of container name => container resource ID."
  value       = { for key, container in azurerm_storage_container.this : key => container.id }
}

output "file_share_ids" {
  description = "Map of file share name => share resource ID."
  value       = { for key, share in azurerm_storage_share.this : key => share.id }
}

output "lifecycle_policy_id" {
  description = "ID of the storage management policy (null when no lifecycle rules are set)."
  value       = one(azurerm_storage_management_policy.this[*].id)
}

output "private_endpoint_ids" {
  description = "Map of subresource => private endpoint ID."
  value       = { for key, pep in azurerm_private_endpoint.this : key => pep.id }
}

output "private_endpoint_ip_addresses" {
  description = "Map of subresource => private endpoint IP address."
  value       = { for key, pep in azurerm_private_endpoint.this : key => pep.private_service_connection[0].private_ip_address }
}
