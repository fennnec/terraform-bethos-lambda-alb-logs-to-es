data "aws_region" "current" {
}

data "aws_subnet" "default" {
  count = length(var.subnets)
  id    = var.subnets[count.index]
}

data "aws_s3_bucket" "log_bucket" {
  bucket = var.s3_bucket
}

data "aws_route_table" "private" {
  count = length(var.subnets)
  subnet_id = var.subnets[count.index]
}