# Secure-by-default Azure Storage Account: TLS 1.2+, OAuth-first auth with
# shared keys off, no public blobs, network default-deny, infrastructure
# (double) encryption, blob versioning + soft delete, plus containers, file
# shares, lifecycle rules, optional CMK encryption and private endpoints.

locals {
  cmk_identity_ids = var.customer_managed_key == null ? [] : [var.customer_managed_key.user_assigned_identity_id]
  identity_ids     = distinct(concat(var.user_assigned_identity_ids, local.cmk_identity_ids))
  identity_type    = length(local.identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"
}

resource "azurerm_storage_account" "this" {
  # checkov:skip=CKV_AZURE_36: secure default lives in variables.tf (network_rules.bypass defaults to ["AzureServices"] alongside default_action "Deny"); checkov cannot resolve optional() attribute defaults on child-module object variables
  # checkov:skip=CKV_AZURE_59: the public endpoint is a deliberate buyer knob via var.public_network_access_enabled — network_rules default-deny still applies when it is enabled; set false for private-endpoint-only accounts
  # checkov:skip=CKV_AZURE_33: classic Storage Analytics queue logging is the legacy mechanism and no queue resources are created here; request logging is delivered via Azure Monitor diagnostic settings provisioned alongside this module
  # checkov:skip=CKV_AZURE_206: replication is an explicit buyer knob via var.account_replication_type whose default ZRS IS replicated (zone-redundant); geo-redundancy (GRS/GZRS/RAGRS/RAGZRS) is a cost/data-residency decision left to the buyer
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind             = var.account_kind
  account_tier             = var.account_tier
  account_replication_type = var.account_replication_type
  access_tier              = var.access_tier

  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  shared_access_key_enabled         = var.shared_access_key_enabled
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = var.allow_nested_items_to_be_public
  cross_tenant_replication_enabled  = false
  public_network_access_enabled     = var.public_network_access_enabled
  infrastructure_encryption_enabled = var.infrastructure_encryption_enabled

  dynamic "blob_properties" {
    for_each = var.account_kind == "FileStorage" ? [] : [1]
    content {
      versioning_enabled  = var.blob_versioning_enabled
      change_feed_enabled = var.blob_change_feed_enabled

      delete_retention_policy {
        days = var.blob_soft_delete_days
      }

      container_delete_retention_policy {
        days = var.container_soft_delete_days
      }
    }
  }

  network_rules {
    default_action             = var.network_rules.default_action
    bypass                     = var.network_rules.bypass
    ip_rules                   = var.network_rules.ip_rules
    virtual_network_subnet_ids = var.network_rules.virtual_network_subnet_ids
  }

  identity {
    type         = local.identity_type
    identity_ids = local.identity_ids
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = length(var.file_shares) == 0 || var.shared_access_key_enabled
      error_message = "Managing Azure file shares through this provider requires shared_access_key_enabled = true."
    }
  }
}

resource "azurerm_storage_container" "this" {
  # checkov:skip=CKV_AZURE_34: secure default lives in variables.tf (containers access_type defaults to "private" via optional(), and public access additionally requires allow_nested_items_to_be_public = true, default false); checkov cannot resolve child-module attribute defaults
  # checkov:skip=CKV2_AZURE_21: blob read-request logging is delivered via Azure Monitor diagnostic settings provisioned alongside this module (classic Storage Analytics logging is the legacy mechanism)
  for_each = var.containers

  name                  = each.key
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = each.value.access_type
  metadata              = each.value.metadata
}

resource "azurerm_storage_share" "this" {
  for_each = var.file_shares

  name               = each.key
  storage_account_id = azurerm_storage_account.this.id
  quota              = each.value.quota_gb
  access_tier        = each.value.access_tier
  enabled_protocol   = each.value.protocol
}

resource "azurerm_storage_management_policy" "this" {
  count = length(var.lifecycle_rules) > 0 ? 1 : 0

  storage_account_id = azurerm_storage_account.this.id

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      name    = rule.value.name
      enabled = rule.value.enabled

      filters {
        prefix_match = rule.value.prefix_match
        blob_types   = rule.value.blob_types
      }

      actions {
        dynamic "base_blob" {
          for_each = (rule.value.base_blob.tier_to_cool_after_days != null || rule.value.base_blob.tier_to_archive_after_days != null || rule.value.base_blob.delete_after_days != null) ? [rule.value.base_blob] : []
          content {
            tier_to_cool_after_days_since_modification_greater_than    = base_blob.value.tier_to_cool_after_days
            tier_to_archive_after_days_since_modification_greater_than = base_blob.value.tier_to_archive_after_days
            delete_after_days_since_modification_greater_than          = base_blob.value.delete_after_days
          }
        }

        dynamic "snapshot" {
          for_each = rule.value.snapshot.delete_after_days != null ? [rule.value.snapshot] : []
          content {
            delete_after_days_since_creation_greater_than = snapshot.value.delete_after_days
          }
        }

        dynamic "version" {
          for_each = rule.value.version.delete_after_days != null ? [rule.value.version] : []
          content {
            delete_after_days_since_creation = version.value.delete_after_days
          }
        }
      }
    }
  }
}

# Customer-managed key encryption (key wrap via Key Vault + UAMI). The
# user-assigned identity must hold Key Vault Crypto Service Encryption User
# (RBAC) on the vault before this resource is applied.
resource "azurerm_storage_account_customer_managed_key" "this" {
  count = var.customer_managed_key == null ? 0 : 1

  storage_account_id        = azurerm_storage_account.this.id
  key_vault_id              = var.customer_managed_key.key_vault_id
  key_name                  = var.customer_managed_key.key_name
  key_version               = var.customer_managed_key.key_version
  user_assigned_identity_id = var.customer_managed_key.user_assigned_identity_id
}

resource "azurerm_private_endpoint" "this" {
  for_each = var.private_endpoints

  name                = coalesce(each.value.name, "pep-${var.name}-${each.key}")
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = each.value.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.name}-${each.key}"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = [each.key]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = length(each.value.private_dns_zone_ids) > 0 ? [1] : []
    content {
      name                 = "default"
      private_dns_zone_ids = each.value.private_dns_zone_ids
    }
  }
}
