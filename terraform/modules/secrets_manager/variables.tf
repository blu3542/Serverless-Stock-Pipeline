variable "project_name" { type = string }
variable "environment"  { type = string }
variable "stock_api_key" {
  type      = string
  sensitive = true
}
