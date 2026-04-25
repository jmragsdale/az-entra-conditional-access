# ---------------------------------------------------------------------------
# PIM — Privileged Identity Management role policies
#
# Each role below is configured eligibility-only. Activation requires:
#   - MFA at activation time
#   - Justification text
#   - For high-impact roles, approval by another admin
#   - Hard maximum activation duration
#
# Requires Entra ID P2 license. The azuread_directory_role data source pulls
# the well-known role definition by display name.
# ---------------------------------------------------------------------------

locals {
  pim_roles = {
    global_admin = {
      role_name           = "Global Administrator"
      max_duration_hours  = 1
      require_approval    = true
      require_ticket_info = true
    }
    privileged_role_admin = {
      role_name           = "Privileged Role Administrator"
      max_duration_hours  = 1
      require_approval    = true
      require_ticket_info = true
    }
    security_admin = {
      role_name           = "Security Administrator"
      max_duration_hours  = 4
      require_approval    = false
      require_ticket_info = true
    }
    user_admin = {
      role_name           = "User Administrator"
      max_duration_hours  = 8
      require_approval    = false
      require_ticket_info = true
    }
    ca_admin = {
      role_name           = "Conditional Access Administrator"
      max_duration_hours  = 4
      require_approval    = true
      require_ticket_info = true
    }
  }
}

data "azuread_directory_role" "pim_roles" {
  for_each     = local.pim_roles
  display_name = each.value.role_name
}

resource "azuread_role_management_policy" "pim" {
  for_each            = local.pim_roles
  role_definition_id  = data.azuread_directory_role.pim_roles[each.key].template_id
  scope               = "/"

  # Cap maximum activation duration
  activation_rules {
    maximum_duration                   = "PT${each.value.max_duration_hours}H"
    require_approval                   = each.value.require_approval
    require_justification              = true
    require_ticket_info                = each.value.require_ticket_info
    require_multifactor_authentication = true

    dynamic "approval_stage" {
      for_each = each.value.require_approval ? [1] : []
      content {
        primary_approver {
          object_id = azuread_group.admins.object_id
          type      = "groupMembers"
        }
      }
    }
  }

  # Notification rules — activation events go to admins group
  notification_rules {
    eligible_activations {
      admin_notifications {
        notification_level    = "All"
        default_recipients    = true
        additional_recipients = []
      }
    }
  }
}
