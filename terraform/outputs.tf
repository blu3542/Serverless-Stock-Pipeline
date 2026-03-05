output "api_endpoint" {
  description = "Base URL for the GET /movers endpoint"
  value       = module.api_gateway.api_endpoint
}

output "frontend_url" {
  description = "S3 static website URL"
  value       = "http://${module.s3.website_url}"
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = module.dynamodb.table_name
}

output "s3_bucket_name" {
  description = "Frontend S3 bucket name (needed for deploy script)"
  value       = module.s3.bucket_name
}
