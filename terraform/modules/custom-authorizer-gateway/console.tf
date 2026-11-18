# =============================================================================
# Console exposure: internet-facing ALB (Phase 4 PoC)
#
# The PoC web console (console/apps/web in rosa-seaplane-api, static nginx)
# served on an internet-facing ALB. Browsers load the console here, then
# call the custom-authorizer API Gateway directly (CORS) with PKCE tokens
# from the Keycloak behind CloudFront.
#
# PoC simplification: HTTP only (the PKCE redirect origin is the ALB DNS
# name). Serve behind CloudFront with HTTPS + a custom domain before
# anything beyond the PoC, mirroring the Keycloak exposure in keycloak.tf.
# =============================================================================

resource "aws_lb" "console" {
  name               = "${local.name}-console"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.console_alb.id]
  subnets            = var.public_subnet_ids

  tags = merge(local.common_tags, { Name = "${local.name}-console" })
}

resource "aws_lb_target_group" "console" {
  name        = "${local.name}-console"
  port        = var.console_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Required for TargetGroupBinding

  health_check {
    enabled             = true
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = merge(local.common_tags, {
    Name                   = "${local.name}-console"
    "eks:eks-cluster-name" = var.cluster_name
  })
}

resource "aws_lb_listener" "console_http" {
  load_balancer_arn = aws_lb.console.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.console.arn
  }
}

resource "aws_security_group" "console_alb" {
  name        = "${local.name}-console-alb"
  description = "Console ALB ingress (public, PoC)"
  vpc_id      = var.vpc_id

  revoke_rules_on_delete = false

  tags = merge(local.common_tags, { Name = "${local.name}-console-alb" })
}

resource "aws_vpc_security_group_ingress_rule" "console_alb_http" {
  security_group_id = aws_security_group.console_alb.id
  description       = "Allow public HTTP to the PoC console"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
  tags              = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "console_alb_to_targets" {
  security_group_id            = aws_security_group.console_alb.id
  description                  = "Allow traffic to console pods"
  ip_protocol                  = "tcp"
  from_port                    = var.console_port
  to_port                      = var.console_port
  referenced_security_group_id = var.node_security_group_id
  tags                         = local.common_tags
}
