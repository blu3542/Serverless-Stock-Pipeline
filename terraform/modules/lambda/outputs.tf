output "ingestion_lambda_arn"  { value = aws_lambda_function.ingestion.arn }
output "ingestion_lambda_name" { value = aws_lambda_function.ingestion.function_name }
output "retrieval_lambda_arn"  { value = aws_lambda_function.retrieval.arn }
output "retrieval_lambda_name" { value = aws_lambda_function.retrieval.function_name }
output "analyst_lambda_arn"    { value = aws_lambda_function.analyst.arn }
output "analyst_lambda_name"   { value = aws_lambda_function.analyst.function_name }
