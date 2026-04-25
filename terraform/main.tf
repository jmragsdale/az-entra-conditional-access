terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.50"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

data "azuread_client_config" "current" {}

# ---------------------------------------------------------------------------
# Logging — sign-in & audit logs land in a Log Analytics workspace
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "rg" {
  name     = "rg-entra-security"
  location = var.location
  tags     = local.tags
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-entra-security"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 90
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# Named locations — trusted countries allow-list
# ---------------------------------------------------------------------------
resource "azuread_named_location" "trusted_countries" {
  display_name = "Trusted-Countries"
  country {
    countries_and_regions = var.trusted_countries
  }
}

# ---------------------------------------------------------------------------
# Groups
# ---------------------------------------------------------------------------
resource "azuread_group" "admins" {
  display_name     = "aad-admins"
  security_enabled = true
  description      = "Members subject to admin-grade Conditional Access (compliant device required)"
}

resource "azuread_group" "breakglass" {
  display_name     = "aad-breakglass"
  security_enabled = true
  description      = "Break-glass accounts — excluded from all Conditional Access policies"
}

# ---------------------------------------------------------------------------
# CA-001 — Block legacy authentication
# ---------------------------------------------------------------------------
resource "azuread_conditional_access_policy" "block_legacy_auth" {
  display_name = "CA-001-Block-Legacy-Auth"
  state        = var.policy_state

  conditions {
    client_app_types = ["exchangeActiveSync", "other"]

    applications {
      included_applications = ["All"]
    }
    users {
      included_users  = ["All"]
      excluded_groups = [azuread_group.breakglass.object_id]
    }
  }

  grant_controls {
    operator          = "OR"
    built_in_controls = ["block"]
  }
}

# ---------------------------------------------------------------------------
# CA-002 — Require MFA for all users
# ---------------------------------------------------------------------------
resource "azuread_conditional_access_policy" "require_mfa" {
  display_name = "CA-002-Require-MFA-All-Users"
  state        = var.policy_state

  conditions {
    client_app_types = ["all"]

    applications {
      included_applications = ["All"]
    }
    users {
      included_users  = ["All"]
      excluded_groups = [azuread_group.breakglass.object_id]
    }
  }

  grant_controls {
    operator          = "OR"
    built_in_controls = ["mfa"]
  }
}

# ---------------------------------------------------------------------------
# CA-003 — Admin portals require compliant device + MFA
# ---------------------------------------------------------------------------
resource "azuread_conditional_access_policy" "admin_compliant_device" {
  display_name = "CA-003-Admin-Portals-Compliant-Device"
  state        = var.policy_state

  conditions {
    client_app_types = ["all"]

    applications {
      # MicrosoftAdminPortals app id is well-known
      included_applications = ["MicrosoftAdminPortals"]
    }
    users {
      included_groups = [azuread_group.admins.object_id]
      excluded_groups = [azuread_group.breakglass.object_id]
    }
  }

  grant_controls {
    operator          = "AND"
    built_in_controls = ["mfa", "compliantDevice"]
  }
}

# ---------------------------------------------------------------------------
# CA-004 — Block sign-ins from outside trusted countries
# ---------------------------------------------------------------------------
resource "azuread_conditional_access_policy" "geo_block" {
  display_name = "CA-004-Block-Untrusted-Geographies"
  state        = var.policy_state

  conditions {
    client_app_types = ["all"]

    applications {
      included_applications = ["All"]
    }
    users {
      included_users  = ["All"]
      excluded_groups = [azuread_group.breakglass.object_id]
    }
    locations {
      included_locations = ["All"]
      excluded_locations = [azuread_named_location.trusted_countries.id]
    }
  }

  grant_controls {
    operator          = "OR"
    built_in_controls = ["block"]
  }
}

# ---------------------------------------------------------------------------
# CA-005 — Risk-based gating
# ---------------------------------------------------------------------------
resource "azuread_conditional_access_policy" "high_risk_block" {
  display_name = "CA-005-Block-High-Sign-In-Risk"
  state        = var.policy_state

  conditions {
    client_app_types  = ["all"]
    sign_in_risk_levels = ["high"]

    applications {
      included_applications = ["All"]
    }
    users {
      included_users  = ["All"]
      excluded_groups = [azuread_group.breakglass.object_id]
    }
  }

  grant_controls {
    operator          = "OR"
    built_in_controls = ["block"]
  }
}

resource "azuread_conditional_access_policy" "medium_risk_mfa" {
  display_name = "CA-005b-Medium-Risk-MFA-And-PwdChange"
  state        = var.policy_state

  conditions {
    client_app_types  = ["all"]
    sign_in_risk_levels = ["medium"]

    applications {
      included_applications = ["All"]
    }
    users {
      included_users  = ["All"]
      excluded_groups = [azuread_group.breakglass.object_id]
    }
  }

  grant_controls {
    operator          = "AND"
    built_in_controls = ["mfa", "passwordChange"]
  }
}

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------
locals {
  tags = {
    Project     = "entra-security"
    ManagedBy   = "terraform"
    Environment = var.environment
  }
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.law.id
}

output "admins_group_object_id" {
  value = azuread_group.admins.object_id
}

output "breakglass_group_object_id" {
  value       = azuread_group.breakglass.object_id
  description = "Add break-glass accounts to this group — they are excluded from every CA policy"
}

output "trusted_countries_location_id" {
  value = azuread_named_location.trusted_countries.id
}

# ---------------------------------------------------------------------------
# PIM role settings
# Note: azuread_role_management_policy resources require the AAD P2 SKU.
# These are kept in pim.tf for clarity — see that file.
# ---------------------------------------------------------------------------
