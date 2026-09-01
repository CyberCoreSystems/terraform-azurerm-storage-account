terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0, < 5.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "00000000-0000-0000-0000-000000000000"

  # Required for data-plane container management while shared keys are off.
  storage_use_azuread = true
}

module "storage" {
  source = "../../"

  name                = "stiacbazaarexample001"
  resource_group_name = "rg-storage-example"
  location            = "westeurope"

  containers = {
    raw = {}
    curated = {
      metadata = { tier = "silver" }
    }
  }

  lifecycle_rules = [
    {
      name         = "tier-and-expire-raw"
      prefix_match = ["raw/"]
      base_blob = {
        tier_to_cool_after_days    = 30
        tier_to_archive_after_days = 90
        delete_after_days          = 365
      }
      snapshot = { delete_after_days = 30 }
      version  = { delete_after_days = 90 }
    }
  ]

  network_rules = {
    default_action = "Deny"
    ip_rules       = ["203.0.113.0/24"]
  }

  tags = {
    environment = "example"
    managed_by  = "iac-bazaar"
  }
}

output "storage_account_id" {
  value = module.storage.id
}

output "primary_blob_endpoint" {
  value = module.storage.primary_blob_endpoint
}
