resource "aws_cloudwatch_event_rule" "daily_ingestion" {
  name                = "${var.project_name}-daily-ingest-${var.environment}"
  description         = "Fires daily after US market close to ingest top stock mover"
  schedule_expression = var.schedule_expression
  state               = "ENABLED"

  tags = { Name = "${var.project_name}-event-rule-${var.environment}" }
}

resource "aws_cloudwatch_event_target" "ingestion_lambda" {
  rule = aws_cloudwatch_event_rule.daily_ingestion.name
  arn  = var.ingestion_lambda_arn
}

# Allow EventBridge to invoke the ingestion Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = var.ingestion_lambda_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_ingestion.arn
}
