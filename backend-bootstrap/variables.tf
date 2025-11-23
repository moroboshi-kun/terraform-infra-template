# ============================================================================
# backend-bootstrap/variables.tf
# ============================================================================

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project short name"
  type        = string
}

variable "env" {
  description = "Environment (dev, test, prod)"
  type        = string
}



