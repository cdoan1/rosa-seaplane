# =============================================================================
# Keycloak exposure: internet-facing ALB + CloudFront (Phase 4 PoC)
#
# The PoC token issuer (Keycloak on the RC) is served behind CloudFront:
#
#   browser --HTTPS--> CloudFront (default *.cloudfront.net cert)
#               --HTTP--> internet-facing ALB --SG-restricted-to-CloudFront-->
#               Keycloak pods (TargetGroupBinding from the keycloak chart)
#
# The CloudFront domain becomes the token issuer URL (KC_HOSTNAME), the same
# value wired into RH_TOKEN_ISSUER / rh_token_jwks_url. Cache behaviors pass
# everything through uncached — tokens, JWKS, and admin paths must never be
# cached.
#
# PoC simplifications (recorded in poc-decisions.md D-P4-token):
#   - default CloudFront certificate (no custom domain / ACM / route53);
#     changing the issuer URL later re-mints links, acceptable for a PoC.
#   - CloudFront -> ALB origin over HTTP; upgrade to an HTTPS origin with an
#     ACM cert before anything beyond the PoC.
# =============================================================================

data "aws_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# -----------------------------------------------------------------------------
# Internet-facing ALB for Keycloak, reachable only from CloudFront.
# -----------------------------------------------------------------------------

resource "aws_lb" "keycloak" {
  name               = "${local.name}-keycloak"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.keycloak_alb.id]
  subnets            = var.public_subnet_ids

  tags = merge(local.common_tags, { Name = "${local.name}-keycloak" })
}

resource "aws_lb_target_group" "keycloak" {
  name        = "${local.name}-keycloak"
  port        = var.keycloak_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Required for TargetGroupBinding

  health_check {
    enabled             = true
    path                = "/health/ready"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = merge(local.common_tags, {
    Name                   = "${local.name}-keycloak"
    "eks:eks-cluster-name" = var.cluster_name
  })
}

resource "aws_lb_listener" "keycloak_http" {
  load_balancer_arn = aws_lb.keycloak.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.keycloak.arn
  }
}

resource "aws_security_group" "keycloak_alb" {
  name        = "${local.name}-keycloak-alb"
  description = "Keycloak ALB ingress (CloudFront only)"
  vpc_id      = var.vpc_id

  revoke_rules_on_delete = false

  tags = merge(local.common_tags, { Name = "${local.name}-keycloak-alb" })
}

resource "aws_vpc_security_group_ingress_rule" "keycloak_alb_from_cloudfront" {
  security_group_id = aws_security_group.keycloak_alb.id
  description       = "Allow traffic from CloudFront origins only"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  prefix_list_id    = data.aws_prefix_list.cloudfront.id
  tags              = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "keycloak_alb_to_targets" {
  security_group_id            = aws_security_group.keycloak_alb.id
  description                  = "Allow traffic to Keycloak pods"
  ip_protocol                  = "tcp"
  from_port                    = var.keycloak_port
  to_port                      = var.keycloak_port
  referenced_security_group_id = var.node_security_group_id
  tags                         = local.common_tags
}

# -----------------------------------------------------------------------------
# CloudFront distribution (uncached pass-through to the ALB origin)
# -----------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "keycloak" {
  enabled     = true
  comment     = "PoC Keycloak (RH-token issuer) for ${local.name}"
  price_class = "PriceClass_100"

  origin {
    domain_name = aws_lb.keycloak.dns_name
    origin_id   = "keycloak-alb"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # PoC; see file header
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "keycloak-alb"
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = true
      # Forward everything: Authorization, cookies (Keycloak sessions),
      # X-Forwarded-* that KC_PROXY_HEADERS relies on.
      headers = ["*"]
      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(local.common_tags, { Name = "${local.name}-keycloak" })

  depends_on = [aws_lb.keycloak]
}
