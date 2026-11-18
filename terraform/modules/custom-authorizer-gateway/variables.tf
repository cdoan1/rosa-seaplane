variable "regional_id" {
  type        = string
  description = "Regional identifier used for resource naming."
}

variable "vpc_id" {
  type        = string
  description = "VPC for the ALB, VPC Link, and security groups."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets for the ALB and VPC Link."
}

variable "node_security_group_id" {
  type        = string
  description = "EKS node security group (ALB forwards to platform-api pods)."
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name (tagged on the target group for TargetGroupBinding)."
}

variable "target_port" {
  type        = number
  default     = 8080
  description = "Platform API pod port."
}

variable "health_check_path" {
  type        = string
  default     = "/api/v0/ready"
  description = "Platform API readiness path for target group health checks."
}

variable "stage_name" {
  type        = string
  default     = "api"
  description = "API Gateway stage name."
}

variable "enable_access_logs" {
  type        = bool
  default     = true
  description = "Enable CloudWatch access logs for the stage."
}

variable "authorizer_image_uri" {
  type        = string
  description = "ECR image URI of the seaplane-authorizer Lambda (built from rosa-seaplane-api)."
}

variable "rh_token_issuer" {
  type        = string
  description = "Expected token issuer (the PoC Keycloak behind CloudFront)."
}

variable "rh_token_jwks_url" {
  type        = string
  description = "Issuer JWKS endpoint used for token verification."
}

variable "rh_token_audience" {
  type        = string
  default     = ""
  description = "Expected token audience; empty skips audience checking."
}

variable "authorizer_cache_ttl_seconds" {
  type        = number
  default     = 300
  description = "Flow 2b decision cache TTL; decisions also expire with their tokens."
}

variable "linking_table_name" {
  type        = string
  default     = ""
  description = "Explicit linking table name; defaults to <name>-links."
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnets for the internet-facing Keycloak ALB."
}

variable "keycloak_port" {
  type        = number
  default     = 8080
  description = "Keycloak pod port (chart's keycloak.service.port)."
}

variable "console_port" {
  type        = number
  default     = 8080
  description = "Console pod port (chart's console.service.port)."
}
