resource "aws_iam_role" "benthos-role" {
  name = "benthos-s3-read-role"
  assume_role_policy = jsonencode(
  {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "lambdapolicy" {
  policy = jsonencode(
  {
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "ESPermission"
        Effect = "Allow"
        Action = [
          "es:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"]
        Resource = [
          data.aws_s3_bucket.log_bucket.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          "${data.aws_s3_bucket.log_bucket.arn}/*"]
      }
    ]
  }
  )
}

resource "aws_iam_role_policy_attachment" "policy_attachment" {
  role = aws_iam_role.benthos-role.name
  policy_arn = aws_iam_policy.lambdapolicy.arn
}

resource "aws_iam_role_policy_attachment" "policy_attachment_vpc" {
  count = length(var.subnets) > 0 ? 1 : 0
  role = aws_iam_role.benthos-role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_vpc_endpoint" "s3_endpoint" {
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_id = data.aws_subnet.default.0.vpc_id
  route_table_ids = data.aws_route_table.private.*.route_table_id
}

resource "aws_security_group" "default" {
  egress {
    from_port = 0
    protocol = "TCP"
    to_port = 65535
    cidr_blocks = [
      "0.0.0.0/0"]
  }
  ingress {
    from_port = 0
    protocol = "TCP"
    to_port = 65535
    cidr_blocks = [
      "0.0.0.0/0"]
  }
  name = "benthos-lambda-sg"
  vpc_id = data.aws_subnet.default.0.vpc_id
}


resource "aws_lambda_function" "default" {
  function_name = var.name
  handler = "benthos-lambda"
  role = aws_iam_role.benthos-role.arn
  runtime = "go1.x"
  filename = "${path.module}/benthos-lambda_3.40.0_linux_amd64.zip"
  timeout = 120
  vpc_config {
    security_group_ids = aws_security_group.default.*.id
    subnet_ids = var.subnets
  }
  environment {
    variables = {
      BENTHOS_CONFIG = var.config != "" ? var.config : yamlencode({
        resources = {
          caches = {
            nurgle = {
              s3 = {
                region = data.aws_region.current.name
                bucket = var.s3_bucket
                timeout = "30s"
              }
            }
          }
        }
        pipeline = {
          processors = [
            {
              bloblang = "root = Records.*.s3.object.key"
            },
            {
              unarchive = {
                format = "json_array"
              }
            },
            {
              log = {
                level = "INFO"
                message = "reading file $${!json()}"
              }
            },
            {
              cache = {
                resource = "nurgle"
                operator = "get"
                key = "$${!json()}"
              }
            },
            {
              catch = [
                {
                  log = {
                    level = "ERROR"
                    message = "cache failed with $${!error()}"
                  }
                }
              ]
            },
            {
              decompress = {
                algorithm = "gzip"
              }
            },
            {
              unarchive = {
                format = "lines"
              }
            },
            {
              log = {
                level = "DEBUG"
                message = "read lines from file: $${!json()}"
              }
            },
            {
              jq = {
                raw = true,
                query = "{\"logline\": .}"
              }
            },
            {
              catch = [
                {
                  log = {
                    level = "ERROR"
                    message = "Failed with error $${!error()}"
                  }
                }
              ]
            }
          ]
        }
        output = {
          elasticsearch = {
            urls = [
              "https://${var.es_endpoint}"]
            index = "${var.index_name}-$${!timestamp(\"2006-01-02\")}"
            type = "_doc"
            pipeline = var.es_pipeline
            sniff = false
            healthcheck = false
            tls = {
              enabled = true
              skip_cert_verify = true
            }
            aws = {
              enabled = true
              region = data.aws_region.current.name
              /*              credentials = {
                role = aws_iam_role.benthos-role.arn
              }*/
            }
          }
        }
      }
      )
    }
  }
}

resource "aws_s3_bucket_notification" "default" {
  bucket = var.s3_bucket
  lambda_function {
    lambda_function_arn = aws_lambda_function.default.arn
    events = [
      "s3:ObjectCreated:*"]
    filter_suffix = ".log.gz"
    filter_prefix = "AWSLogs/147429388953/elasticloadbalancing/"
  }
}

/*
vpc-es-log-cluster-vwp6xihvke3twiexjqknacbuae.eu-central-1.es.amazonaws.com
147429388953-alb-access-logs-main-lb
["subnet-0022ce6da60261946","subnet-08446206d1b7726c6","subnet-0daaefb84d8049a87"]
eu-central-1
*/