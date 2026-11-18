output "api_id" {
  value = aws_api_gateway_rest_api.main.id
}

output "invoke_url" {
  value = aws_api_gateway_stage.main.invoke_url
}

output "linking_table_name" {
  value = aws_dynamodb_table.linking.name
}

output "linking_table_arn" {
  value = aws_dynamodb_table.linking.arn
}

output "alb_arn" {
  value = aws_lb.platform.arn
}

output "target_group_arn" {
  value = aws_lb_target_group.platform.arn
}
