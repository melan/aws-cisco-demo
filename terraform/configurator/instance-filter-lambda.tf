locals {
  instance_filter_function_name = "${var.name_prefix}-instance-filter"
}

data "aws_iam_policy_document" "assume-lambda" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "instance_filter_role" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [aws_cloudwatch_log_group.instance_filter.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["ec2:Describe*"]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["codebuild:StartBuild"]
    resources = [aws_codebuild_project.configurator.arn]
  }
}

resource "aws_iam_role" "instance_filter" {
  assume_role_policy = data.aws_iam_policy_document.assume-lambda.json
  name               = "${var.name_prefix}-instance-filter"
}

resource "aws_iam_policy" "instance_filter" {
  policy = data.aws_iam_policy_document.instance_filter_role.json
  name   = "${var.name_prefix}-instance-filter"
}

resource "aws_iam_role_policy_attachment" "instance-filter" {
  policy_arn = aws_iam_policy.instance_filter.arn
  role       = aws_iam_role.instance_filter.id
}

resource "aws_lambda_function" "instance_filter" {
  function_name     = "${var.name_prefix}-instance-filter"
  handler           = "function.handler"
  role              = aws_iam_role.instance_filter.arn
  runtime           = "python3.7"
  s3_bucket         = data.aws_s3_bucket_object.instance_filter_lambda_object.bucket
  s3_key            = data.aws_s3_bucket_object.instance_filter_lambda_object.key
  s3_object_version = data.aws_s3_bucket_object.instance_filter_lambda_object.version_id
  memory_size       = 256
  timeout           = 300

  environment {
    variables = {
      # 1 - DEBUG, 10 - INFO
      LAMBDA_LOG_LEVEL        = 1
      INSTANCE_PRODUCT_CODE   = var.cisco_csr_product_code
      INSTANCE_PRODUCT_SOURCE = "marketplace"
      INSTANCE_VPC_ID         = var.vpc_id
      BUILD_PROJECT           = aws_codebuild_project.configurator.name
      AWS_VPN_REGIONS         = var.aws_vpn_regions
      PRIVATE_ADDRESS_SPACE   = var.private_address_space
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.instance_filter,
    aws_iam_role_policy_attachment.instance-filter
  ]
}

resource "aws_sns_topic_subscription" "instance-filter" {
  endpoint  = aws_lambda_function.instance_filter.arn
  protocol  = "lambda"
  topic_arn = aws_sns_topic.router-instance-notifications.arn
}

resource "aws_lambda_permission" "instance-filter" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_filter.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.router-instance-notifications.arn
}

resource "aws_cloudwatch_log_group" "instance_filter" {
  name              = "/aws/lambda/${local.instance_filter_function_name}"
  retention_in_days = 1
}
