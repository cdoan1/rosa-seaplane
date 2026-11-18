# =============================================================================
# Custom-Authorizer API Gateway (Phase 4 PoC)
#
# Public REST API authenticated by the seaplane-authorizer Lambda (RH token
# -> linked ARN), emitting the same identity headers as the AWS_IAM
# gateway. Design: docs/poc/preflight-ui-login/phase-4-ui-auth-path.md in
# rosa-seaplane-api. Configured from regional_cluster.custom_authorizer
# (config/defaults.yaml), the same source that renders the platformApi
# linking helm values — one source for terraform and the chart, like
# authz_tables.
# =============================================================================

variable "custom_authorizer" {
  description = "RH-token custom-authorizer gateway (Phase 4 PoC). Null or enabled=false leaves everything uncreated."
  type = object({
    enabled                      = bool
    table                        = string
    authorizer_image_uri         = string
    rh_token_issuer              = string
    rh_token_jwks_url            = string
    rh_token_audience            = optional(string, "")
    authorizer_cache_ttl_seconds = optional(number, 300)
  })
  default = null
  validation {
    condition = var.custom_authorizer == null || !var.custom_authorizer.enabled ? true : (
      can(regex("^arn:aws(-us-gov)?:ecr.+:.+:.+:.+$", var.custom_authorizer.authorizer_image_uri)) &&
      can(regex("^[A-Za-z0-9_.-]{3,255}$", var.custom_authorizer.table)) &&
      can(regex("^https://.+", var.custom_authorizer.rh_token_issuer)) &&
      can(regex("^https://.+", var.custom_authorizer.rh_token_jwks_url))
    )
    error_message = "enabled requires an ECR image URI, a valid table name, and https issuer/JWKS URLs."
  }
}

locals {
  custom_authorizer                    = var.custom_authorizer == null ? {} : var.custom_authorizer
  enable_custom_authorizer_gateway     = try(local.custom_authorizer.enabled, false)
  custom_authorizer_linking_table_name = try(local.custom_authorizer.table, "")
}

module "custom_authorizer_gateway" {
  count  = local.enable_custom_authorizer_gateway ? 1 : 0
  source = "../../modules/custom-authorizer-gateway"

  regional_id            = var.regional_id
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  public_subnet_ids      = module.vpc.public_subnet_ids
  node_security_group_id = module.regional_cluster.node_security_group_id
  cluster_name           = module.regional_cluster.cluster_name

  authorizer_image_uri         = local.custom_authorizer.authorizer_image_uri
  rh_token_issuer              = local.custom_authorizer.rh_token_issuer
  rh_token_jwks_url            = local.custom_authorizer.rh_token_jwks_url
  rh_token_audience            = try(local.custom_authorizer.rh_token_audience, "")
  authorizer_cache_ttl_seconds = try(local.custom_authorizer.authorizer_cache_ttl_seconds, 300)
  linking_table_name           = local.custom_authorizer_linking_table_name
}

# -----------------------------------------------------------------------------
# Platform API write access to the linking table (pod identity, mirroring
# platform_api_authz in authz.tf). The authorizer Lambda reads the table
# via its own least-privilege role; the API's linking endpoints write it.
# -----------------------------------------------------------------------------

data "aws_partition" "current_ca" {}

resource "aws_iam_role" "platform_api_linking" {
  count = local.enable_custom_authorizer_gateway ? 1 : 0
  name  = "${var.regional_id}-platform-api-linking"
  tags = {
    function = "authorization"
    module   = "regional-cluster"
  }
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy" "platform_api_linking" {
  count = local.enable_custom_authorizer_gateway ? 1 : 0
  name  = "linking-table"
  role  = aws_iam_role.platform_api_linking[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem", "dynamodb:Query",
        "dynamodb:PutItem", "dynamodb:DeleteItem",
      ]
      Resource = [
        "arn:${data.aws_partition.current_ca.partition}:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${local.custom_authorizer_linking_table_name}",
      ]
    }]
  })
}

resource "aws_eks_pod_identity_association" "platform_api_linking" {
  count           = local.enable_custom_authorizer_gateway ? 1 : 0
  cluster_name    = module.regional_cluster.cluster_name
  namespace       = "platform-api"
  service_account = "platform-api-sa"
  role_arn        = aws_iam_role.platform_api_linking[0].arn
  tags = {
    function = "authorization"
    module   = "regional-cluster"
  }
}

output "custom_authorizer_invoke_url" {
  value       = local.enable_custom_authorizer_gateway ? module.custom_authorizer_gateway[0].invoke_url : ""
  description = "Invoke URL of the custom-authorizer API Gateway (empty when disabled)."
}

output "custom_authorizer_linking_table" {
  value       = local.enable_custom_authorizer_gateway ? module.custom_authorizer_gateway[0].linking_table_name : ""
  description = "DynamoDB linking table name (empty when disabled)."
}

output "keycloak_url" {
  value       = local.enable_custom_authorizer_gateway ? module.custom_authorizer_gateway[0].keycloak_url : ""
  description = "Public Keycloak URL — the PoC token issuer (empty when disabled)."
}

output "keycloak_target_group_arn" {
  value       = local.enable_custom_authorizer_gateway ? module.custom_authorizer_gateway[0].keycloak_target_group_arn : ""
  description = "Keycloak ALB target group ARN for the chart's TargetGroupBinding (empty when disabled)."
}

output "console_url" {
  value       = local.enable_custom_authorizer_gateway ? module.custom_authorizer_gateway[0].console_url : ""
  description = "Public PoC console URL (empty when disabled)."
}

output "console_target_group_arn" {
  value       = local.enable_custom_authorizer_gateway ? module.custom_authorizer_gateway[0].console_target_group_arn : ""
  description = "Console ALB target group ARN for the chart's TargetGroupBinding (empty when disabled)."
}
