variable "name" {
  description = "Globally-unique storage account name (3-24 lowercase letters and digits)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "name must be 3-24 characters of lowercase letters and digits only."
  }
}

variable "resource_group_name" {
  description = "Name of an existing resource group."
  type        = string
}

variable "location" {
  description = "Azure region for the storage account."
  type        = string
}

variable "account_kind" {
  description = "Storage account kind."
  type        = string
  default     = "StorageV2"

  validation {
    condition     = contains(["StorageV2", "BlockBlobStorage", "FileStorage"], var.account_kind)
    error_message = "account_kind must be StorageV2, BlockBlobStorage or FileStorage (legacy kinds are not supported by this module)."
  }
}

variable "account_tier" {
  description = "Storage tier. BlockBlobStorage/FileStorage kinds require Premium."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "account_tier must be Standard or Premium."
  }
}

variable "account_replication_type" {
  description = "Replication: LRS, ZRS, GRS, GZRS, RAGRS or RAGZRS. Defaults to zone-redundant."
  type        = string
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], var.account_replication_type)
    error_message = "account_replication_type must be one of LRS, ZRS, GRS, GZRS, RAGRS, RAGZRS."
  }
}

variable "access_tier" {
  description = "Default access tier for blobs."
  type        = string
  default     = "Hot"

  validation {
    condition     = contains(["Hot", "Cool"], var.access_tier)
    error_message = "access_tier must be Hot or Cool."
  }
}

variable "shared_access_key_enabled" {
  description = "Allow shared-key (account key / SAS) authorization. Off by default: use Entra ID. Note: managing containers with keys disabled requires 'storage_use_azuread = true' in your provider block, and file shares require this to be true."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Allow any traffic over the public endpoint (still filtered by network_rules). Set false for private-endpoint-only accounts."
  type        = bool
  default     = true
}

variable "allow_nested_items_to_be_public" {
  description = "Permit containers/blobs to be configured for anonymous public access. Keep false unless you really host public content."
  type        = bool
  default     = false
}

variable "infrastructure_encryption_enabled" {
  description = "Enable infrastructure (double) encryption. Create-time only — cannot be changed later."
  type        = bool
  default     = true
}

variable "blob_versioning_enabled" {
  description = "Enable blob versioning."
  type        = bool
  default     = true
}

variable "blob_change_feed_enabled" {
  description = "Enable the blob change feed."
  type        = bool
  default     = false
}

variable "blob_soft_delete_days" {
  description = "Blob soft-delete retention in days (1-365)."
  type        = number
  default     = 7

  validation {
    condition     = var.blob_soft_delete_days >= 1 && var.blob_soft_delete_days <= 365
    error_message = "blob_soft_delete_days must be between 1 and 365."
  }
}

variable "container_soft_delete_days" {
  description = "Container soft-delete retention in days (1-365)."
  type        = number
  default     = 7

  validation {
    condition     = var.container_soft_delete_days >= 1 && var.container_soft_delete_days <= 365
    error_message = "container_soft_delete_days must be between 1 and 365."
  }
}

variable "network_rules" {
  description = "Account-level network ACLs. Default denies everything except trusted Azure services; add your CIDRs/subnets."
  type = object({
    default_action             = optional(string, "Deny")
    bypass                     = optional(list(string), ["AzureServices"])
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  })
  default = {}

  validation {
    condition     = contains(["Allow", "Deny"], var.network_rules.default_action)
    error_message = "network_rules.default_action must be Allow or Deny."
  }
}

variable "containers" {
  description = "Blob containers keyed by name. access_type defaults to private (blob/container also require allow_nested_items_to_be_public = true)."
  type = map(object({
    access_type = optional(string, "private")
    metadata    = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for container in values(var.containers) : contains(["private", "blob", "container"], container.access_type)])
    error_message = "containers access_type must be private, blob or container."
  }
}

variable "file_shares" {
  description = "Azure Files shares keyed by name. Requires shared_access_key_enabled = true."
  type = map(object({
    quota_gb    = number
    access_tier = optional(string, "Hot")
    protocol    = optional(string, "SMB")
  }))
  default = {}

  validation {
    condition = alltrue([
      for share in values(var.file_shares) :
      share.quota_gb >= 1 && contains(["Hot", "Cool", "TransactionOptimized", "Premium"], share.access_tier) && contains(["SMB", "NFS"], share.protocol)
    ])
    error_message = "file_shares: quota_gb >= 1, access_tier in Hot/Cool/TransactionOptimized/Premium, protocol SMB or NFS."
  }
}

variable "lifecycle_rules" {
  description = "Blob lifecycle management rules: tiering and expiry for base blobs, snapshots and versions (days since modification/creation)."
  type = list(object({
    name         = string
    enabled      = optional(bool, true)
    prefix_match = optional(list(string), [])
    blob_types   = optional(list(string), ["blockBlob"])
    base_blob = optional(object({
      tier_to_cool_after_days    = optional(number)
      tier_to_archive_after_days = optional(number)
      delete_after_days          = optional(number)
    }), {})
    snapshot = optional(object({
      delete_after_days = optional(number)
    }), {})
    version = optional(object({
      delete_after_days = optional(number)
    }), {})
  }))
  default = []
}

variable "customer_managed_key" {
  description = "Customer-managed key encryption. The user-assigned identity needs wrap/unwrap rights (Key Vault Crypto Service Encryption User) on the vault; leave key_version null for auto-rotation to the latest version."
  type = object({
    key_vault_id              = string
    key_name                  = string
    key_version               = optional(string)
    user_assigned_identity_id = string
  })
  default = null
}

variable "user_assigned_identity_ids" {
  description = "Extra user-assigned identity IDs to attach to the account (a system-assigned identity is always created)."
  type        = list(string)
  default     = []
}

variable "private_endpoints" {
  description = "Private endpoints keyed by storage subresource (blob, file, queue, table, dfs, web)."
  type = map(object({
    subnet_id            = string
    private_dns_zone_ids = optional(list(string), [])
    name                 = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.private_endpoints) : contains(["blob", "file", "queue", "table", "dfs", "web"], key)])
    error_message = "private_endpoints keys must be storage subresources: blob, file, queue, table, dfs, web."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
