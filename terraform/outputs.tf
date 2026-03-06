output "api_endpoint" {
  description = "Full URL to GET /movers"
  value       = module.api_gateway.api_endpoint
}

output "frontend_url" {
  description = "S3 static website URL"
  value       = "http://${module.s3.website_url}"
}

output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = module.dynamodb.table_name
}

output "s3_bucket_name" {
  description = "S3 bucket name (needed for frontend deploy)"
  value       = module.s3.bucket_name
}
