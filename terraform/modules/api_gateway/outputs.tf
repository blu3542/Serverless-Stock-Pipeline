output "api_endpoint"      { value = "${aws_api_gateway_stage.main.invoke_url}/movers" }
output "analyst_endpoint"  { value = "${aws_api_gateway_stage.main.invoke_url}/analyst" }
output "api_id"            { value = aws_api_gateway_rest_api.main.id }
