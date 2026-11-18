# =============================================================================
# Integrations
#
# HTTP_PROXY to the internal ALB via VPC Link v2. Identity headers are
# mapped from context.authorizer.* (the custom authorizer's output) —
# the SAME header names the AWS_IAM gateway derives from
# context.identity.*. See identity-header-contract.md in
# rosa-seaplane-api docs/poc/preflight-ui-login/.
#
# X-Amz-Principal-Org-Id is intentionally absent on this path (D-T1).
# =============================================================================

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  integration_http_method = "ANY"
  type                    = "HTTP_PROXY"
  connection_type         = "VPC_LINK"
  connection_id           = aws_apigatewayv2_vpc_link.main.id
  # Required for VPC Link v2 + ALB
  timeout_milliseconds = 29000

  uri = "http://${aws_lb.platform.dns_name}/{proxy}"

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy",

    # Identity headers from the authorizer context (header parity).
    "integration.request.header.X-Amz-Caller-Arn" = "context.authorizer.callerArn"
    "integration.request.header.X-Amz-Account-Id" = "context.authorizer.accountId"
    "integration.request.header.X-Amz-User-Id"    = "context.authorizer.sub",
    # Native gateway context (still available on custom-auth requests).
    "integration.request.header.X-Amz-Source-Ip"  = "context.identity.sourceIp"
    "integration.request.header.X-Amz-Request-Id" = "context.requestId"
  }
}

resource "aws_api_gateway_integration" "root" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_rest_api.main.root_resource_id
  http_method             = aws_api_gateway_method.root.http_method
  integration_http_method = "ANY"
  type                    = "HTTP_PROXY"
  connection_type         = "VPC_LINK"
  connection_id           = aws_apigatewayv2_vpc_link.main.id
  timeout_milliseconds    = 29000

  uri = "http://${aws_lb.platform.dns_name}/"

  request_parameters = {
    "integration.request.header.X-Amz-Caller-Arn" = "context.authorizer.callerArn"
    "integration.request.header.X-Amz-Account-Id" = "context.authorizer.accountId"
    "integration.request.header.X-Amz-User-Id"    = "context.authorizer.sub"
    "integration.request.header.X-Amz-Source-Ip"  = "context.identity.sourceIp"
    "integration.request.header.X-Amz-Request-Id" = "context.requestId"
  }
}
