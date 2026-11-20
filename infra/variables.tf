variable "aws_account_id" {
  description = "Personal AWS account ID verified against the AWS console."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Supply a 12-digit AWS account ID."
  }
}

variable "operator_cidr" {
  description = "Public IPv4 CIDR of the workstation used to access Kubernetes."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.operator_cidr)) && endswith(var.operator_cidr, "/32")
    error_message = "Supply a single public IPv4 address as a /32 CIDR."
  }
}

variable "enable_databases" {
  description = "Provision the Aurora and RDS database comparison for the full experiment."
  type        = bool
  default     = false
}
