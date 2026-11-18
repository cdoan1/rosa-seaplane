# =============================================================================
# Custom-Authorizer API Gateway (Phase 4 PoC)
#
# A public REST API whose authentication is the seaplane-authorizer Lambda
# (REQUEST-type custom authorizer) instead of AWS_IAM. UI requests carry
# an RH bearer token and (for resource routes) a selected ARN; the
# authorizer resolves the token to a linked ARN and the gateway forwards
# the SAME identity header names the AWS_IAM gateway produces, sourced
# from context.authorizer.*.
#
# Design: docs/poc/preflight-ui-login/phase-4-ui-auth-path.md (in
# rosa-seaplane-api). Header contract:
# docs/poc/preflight-ui-login/identity-header-contract.md.
# =============================================================================

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    function  = "platform-api"
    module    = "custom-authorizer-gateway"
    ManagedBy = "terraform"
  }

  name = "${var.regional_id}-custom-auth-api"

  # CORS defaults to the console's own origin (the browser only ever calls
  # the gateway from the console). Wildcard only when explicitly requested.
  cors_allowed_origin = var.cors_allowed_origin != "" ? var.cors_allowed_origin : "http://${aws_lb.console.dns_name}"
}

# -----------------------------------------------------------------------------
# REST API
# -----------------------------------------------------------------------------

resource "aws_api_gateway_rest_api" "main" {
  name        = local.name
  description = "Platform API via RH-token custom authorizer (Phase 4 PoC)"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(local.common_tags, { Name = local.name })
}

# -----------------------------------------------------------------------------
# Lambda Authorizer (REQUEST type)
#
# Reads Authorization (bearer token) and X-Seaplane-Arn (selected ARN).
# Flow 2a (no selected ARN): token-only allow for /api/v0/account_links.
# Flow 2b: verifies the token->ARN link in DynamoDB.
# -----------------------------------------------------------------------------

resource "aws_api_gateway_authorizer" "main" {
  name                             = "${local.name}-authorizer"
  rest_api_id                      = aws_api_gateway_rest_api.main.id
  type                             = "REQUEST"
  authorizer_uri                   = aws_lambda_function.authorizer.invoke_arn
  identity_source                  = "method.request.header.Authorization"
  authorizer_result_ttl_in_seconds = 0 # cache lives inside the Lambda, not the gateway
}

# -----------------------------------------------------------------------------
# Proxy resource and methods
# -----------------------------------------------------------------------------

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.main.id

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_method" "root" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_rest_api.main.root_resource_id
  http_method   = "ANY"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.main.id
}

# -----------------------------------------------------------------------------
# CORS: OPTIONS preflight with a MOCK integration
#
# The console (browser) needs preflight handling; the authorizer is
# bypassed for OPTIONS so preflights never require a token.
# -----------------------------------------------------------------------------

resource "aws_api_gateway_method" "options_proxy" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "options_root" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_rest_api.main.root_resource_id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_proxy" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.options_proxy.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }
}

resource "aws_api_gateway_integration" "options_root" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_rest_api.main.root_resource_id
  http_method = aws_api_gateway_method.options_root.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }
}

resource "aws_api_gateway_method_response" "options_proxy" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.options_proxy.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_proxy" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.options_proxy.http_method
  status_code = aws_api_gateway_method_response.options_proxy.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Authorization,Content-Type,X-Seaplane-Arn,X-Rh-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,PATCH,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${local.cors_allowed_origin}'"
  }

  depends_on = [aws_api_gateway_integration.options_proxy]
}

# -----------------------------------------------------------------------------
# Deployment and Stage
# -----------------------------------------------------------------------------

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_method.proxy.id,
      aws_api_gateway_method.root.id,
      aws_api_gateway_integration.proxy.id,
      aws_api_gateway_integration.root.id,
      aws_api_gateway_authorizer.main.id,
      # OPTIONS/CORS resources: a CORS change must trigger redeployment too.
      aws_api_gateway_method.options_proxy.id,
      aws_api_gateway_method.options_root.id,
      aws_api_gateway_integration.options_proxy.id,
      aws_api_gateway_integration.options_root.id,
      aws_api_gateway_integration_response.options_proxy.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "main" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id
  stage_name    = var.stage_name

  dynamic "access_log_settings" {
    for_each = var.enable_access_logs ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api[0].arn
      format          = "{\"requestId\":\"$context.requestId\",\"ip\":\"$context.identity.sourceIp\",\"requestTime\":\"$context.requestTime\",\"httpMethod\":\"$context.httpMethod\",\"routeKey\":\"$context.routeKey\",\"status\":\"$context.status\",\"protocol\":\"$context.protocol\",\"responseLength\":\"$context.responseLength\"}"
    }
  }

  tags = merge(local.common_tags, { Name = local.name })
}

resource "aws_cloudwatch_log_group" "api" {
  count = var.enable_access_logs ? 1 : 0

  name              = "/aws/apigateway/${local.name}"
  retention_in_days = 30

  tags = local.common_tags
}
