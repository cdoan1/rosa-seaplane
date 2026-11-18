# =============================================================================
# Internal ALB + VPC Link (mirrors the api-gateway module's pattern)
#
# Flow: API Gateway -> VPC Link -> ALB -> Target Group -> platform-api pods
# (registered by the kube-applier / LoadBalancerController TargetGroupBinding)
# =============================================================================

resource "aws_apigatewayv2_vpc_link" "main" {
  name               = local.name
  security_group_ids = [aws_security_group.vpc_link.id]
  subnet_ids         = var.private_subnet_ids

  tags = merge(local.common_tags, { Name = local.name })
}

resource "aws_lb" "platform" {
  name               = local.name
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.private_subnet_ids

  tags = merge(local.common_tags, { Name = local.name })
}

resource "aws_lb_target_group" "platform" {
  name        = local.name
  port        = var.target_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Required for TargetGroupBinding

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = merge(local.common_tags, {
    Name                   = local.name
    "eks:eks-cluster-name" = var.cluster_name
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.platform.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.platform.arn
  }
}
