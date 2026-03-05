output "bucket_name"  { value = aws_s3_bucket.frontend.bucket }
output "bucket_arn"   { value = aws_s3_bucket.frontend.arn }
output "website_url"  { value = aws_s3_bucket_website_configuration.frontend.website_endpoint }
