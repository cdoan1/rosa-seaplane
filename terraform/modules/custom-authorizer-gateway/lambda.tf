# =============================================================================
# Lambda Authorizer, Linking Table, and IAM
#
# The authorizer image is built from rosa-seaplane-api
# (seaplane-authorizer/). Token verification and the link schema are shared
# with the platform API via that repo's pkg/linking.
# =============================================================================

# -----------------------------------------------------------------------------
# Lambda Function
# -----------------------------------------------------------------------------

resource "aws_lambda_function" "authorizer" {
  function_name = "${local.name}-authorizer"
  description   = "RH-token custom authorizer for the platform API (Phase 4 PoC)"
  role          = aws_iam_role.authorizer.arn
  package_type  = "Image"
  image_uri     = var.authorizer_image_uri
  architectures = ["x86_64"]
  timeout       = 10
  memory_size   = 256

  environment {
    variables = {
      LINKING_TABLE     = aws_dynamodb_table.linking.name
      RH_TOKEN_ISSUER   = var.rh_token_issuer
      RH_TOKEN_JWKS_URL = var.rh_token_jwks_url
      RH_TOKEN_AUDIENCE = var.rh_token_audience
      AUTHZ_CACHE_TTL   = tostring(var.authorizer_cache_ttl_seconds)
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-authorizer"
  })
}

resource "aws_lambda_permission" "authorizer" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*"
}

# -----------------------------------------------------------------------------
# IAM: least privilege — read the linking table, write logs.
# -----------------------------------------------------------------------------

resource "aws_iam_role" "authorizer" {
  name = "${local.name}-authorizer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${local.name}-authorizer" })
}

resource "aws_iam_role_policy" "authorizer" {
  name = "${local.name}-authorizer"
  role = aws_iam_role.authorizer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:Query", "dynamodb:GetItem"]
        Resource = aws_dynamodb_table.linking.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.name}-authorizer*"
      },
    ]
  })
}

# -----------------------------------------------------------------------------
# Linking Table (D-T4 schema: PK sub, SK arn)
#
# PoC: owned by this module. The platform API's linking endpoint (via the
# AWS_IAM gateway) writes here; the authorizer reads here. Production will
# move this to the authz-storage config with retention — see
# poc-decisions.md D-T4 for the reconciliation note.
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "linking" {
  name         = var.linking_table_name != "" ? var.linking_table_name : "${local.name}-links"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sub"
  range_key    = "arn"

  attribute {
    name = "sub"
    type = "S"
  }
  attribute {
    name = "arn"
    type = "S"
  }
  # Declared for the AccountIndex GSI below; the application writes
  # accountId on every item (linking.Link.AccountID).
  attribute {
    name = "accountId"
    type = "S"
  }

  # Query by subject is the primary access pattern (ListLinks); the GSI
  # covers account-scoped lookups (all links into one AWS account).
  global_secondary_index {
    name            = "AccountIndex"
    hash_key        = "accountId"
    projection_type = "ALL"
  }

  # Point-in-time recovery is cheap insurance; deletion protection stays
  # off so PoC teardown works (production enables it — poc-decisions D-T4).
  point_in_time_recovery {
    enabled = true
  }
  deletion_protection_enabled = false

  tags = merge(local.common_tags, { Name = "${local.name}-links" })
}
