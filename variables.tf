variable "aws_region" {
  description = "AWS region for all resources."

  type    = string
  default = "us-east-1"
}

variable "aws_access_key_id" {
  description = "AWS access key id"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS secret access key"
  type        = string
  sensitive   = true
}

variable "whoop_client_id" {
  description = "WHOOP application client id"
  type        = string
  sensitive   = true
}

variable "whoop_client_secret" {
  description = "WHOOP application client secret"
  type        = string
  sensitive   = true
}

variable "daily_tracking_db" {
  description = "Daily Tracking notion db table."
  type    = string
  default = "1d88b9e61b494b3ba39e11e01b791902"
}

variable "notion_integration_token" {
  description = "Notion integration token"
  type        = string
  sensitive   = true
}
