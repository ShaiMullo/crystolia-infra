# -----------------------------------------------------------------------------
# DynamoDB Table — Leads
# -----------------------------------------------------------------------------
# PAY_PER_REQUEST = no provisioned capacity, no idle cost.
# You only pay per read/write (~$1.25 per million writes).

resource "aws_dynamodb_table" "leads" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}
