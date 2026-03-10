output "ingestion_lambda_role_arn" { value = aws_iam_role.ingestion_lambda.arn }
output "retrieval_lambda_role_arn" { value = aws_iam_role.retrieval_lambda.arn }
output "analyst_lambda_role_arn"   { value = aws_iam_role.analyst_lambda.arn }
