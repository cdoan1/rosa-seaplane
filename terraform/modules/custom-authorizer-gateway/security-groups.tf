# =============================================================================
# Security Groups (mirrors the api-gateway module's pattern)
#
# 1. VPC Link SG - attached to the VPC Link, allows outbound to ALB
# 2. ALB SG - allows inbound from VPC Link and outbound to target pods
# =============================================================================

resource "aws_security_group" "vpc_link" {
  name        = "${local.name}-vpc-link"
  description = "Security group for custom-authorizer API Gateway VPC Link"
  vpc_id      = var.vpc_id

  # Prevent Terraform from trying to detach VPC Link-managed ENIs
  revoke_rules_on_delete = false

  tags = merge(local.common_tags, { Name = "${local.name}-vpc-link" })
}

resource "aws_vpc_security_group_egress_rule" "vpc_link_to_alb" {
  security_group_id            = aws_security_group.vpc_link.id
  description                  = "Allow traffic to ALB"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.alb.id
  tags                         = local.common_tags
}

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "Security group for internal custom-authorizer API ALB"
  vpc_id      = var.vpc_id

  revoke_rules_on_delete = false

  tags = merge(local.common_tags, { Name = "${local.name}-alb" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_vpc_link" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Allow traffic from VPC Link"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.vpc_link.id
  tags                         = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "alb_to_targets" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Allow traffic to target pods"
  ip_protocol                  = "tcp"
  from_port                    = var.target_port
  to_port                      = var.target_port
  referenced_security_group_id = var.node_security_group_id
  tags                         = local.common_tags
}
