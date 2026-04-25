variable "location" {
  type        = string
  default     = "eastus"
  description = "Azure region for the Log Analytics workspace"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "policy_state" {
  type        = string
  default     = "enabledForReportingButNotEnforced"
  description = "Conditional Access state. Start in report-only; promote to 'enabled' after reviewing impact."
  validation {
    condition     = contains(["enabled", "disabled", "enabledForReportingButNotEnforced"], var.policy_state)
    error_message = "policy_state must be enabled, disabled, or enabledForReportingButNotEnforced."
  }
}

variable "trusted_countries" {
  type        = list(string)
  default     = ["US", "CA", "GB"]
  description = "ISO-3166 country codes considered trusted for sign-ins"
}
