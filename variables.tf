variable "config" {
  type    = string
  default = ""
}

variable "name" {
  type    = string
  default = "benthos-lambda"
}

variable "subnets" {
  type        = list(string)
  description = "List of subnets for this Lambda"
}

variable "es_endpoint" {
  type        = string
  description = "Elasticsearch endpoint"
}

variable "index_name" {
  type        = string
  description = "Name of elasticsearch index. Defaults to alb-logs"
  default     = "alb-logs"
}

variable "es_pipeline" {
  type        = string
  description = "Elasticsearch pipeline to process these documents"
  default     = ""
}

variable "s3_bucket" {
  type        = string
  description = "s3 bucket to attach to"
}

variable "cloudwatch_log_retention_days" {
  type    = number
  default = 14
}