locals {
  configurator_name = "${var.name_prefix}-cisco-csr-configurator"
}

data "aws_iam_policy_document" "assume-codebuild" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["codebuild.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "configurator" {
  statement {
    sid    = "AllowLogging"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [aws_cloudwatch_log_group.configurator.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["ec2:Describe*"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "ec2:CreateNetworkInterfacePermission",
    ]

    resources = [
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.me.account_id}:network-interface/*",
    ]

    condition {
      test     = "StringEquals"
      values   = [data.aws_subnet.management_subnet.arn]
      variable = "ec2:Subnet"
    }

    condition {
      test     = "StringEquals"
      values   = ["codebuild.amazonaws.com"]
      variable = "ec2:AuthorizedService"
    }
  }

  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]

    resources = [
      "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.me.account_id}:secret:${data.aws_secretsmanager_secret.router-ssh-key.name}*",
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${data.aws_s3_bucket_object.ansible_object.bucket}/${data.aws_s3_bucket_object.ansible_object.key}"]
  }
}

resource "aws_iam_policy" "configurator" {
  policy = data.aws_iam_policy_document.configurator.json
  name   = "${var.name_prefix}-configurator"
}

resource "aws_iam_role" "configurator" {
  assume_role_policy = data.aws_iam_policy_document.assume-codebuild.json
  name               = "${var.name_prefix}-configurator"
}

resource "aws_iam_role_policy_attachment" "configurator" {
  policy_arn = aws_iam_policy.configurator.arn
  role       = aws_iam_role.configurator.id
}

data "template_file" "buildspec" {
  template = file("${path.module}/buildspec.yml.tpl")

  vars = {
    region     = data.aws_region.current.name
    account_id = data.aws_caller_identity.me.account_id
    # 1 - DEBUG, 10 - INFO
    log_level = 10
  }
}

resource "aws_codebuild_project" "configurator" {
  name          = local.configurator_name
  build_timeout = "5"
  service_role  = aws_iam_role.configurator.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  cache {
    type = "NO_CACHE"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "amazonlinux:2"
    type            = "LINUX_CONTAINER"
    privileged_mode = false
  }

  source {
    type      = "S3"
    location  = "${data.aws_s3_bucket_object.ansible_object.bucket}/${data.aws_s3_bucket_object.ansible_object.key}"
    buildspec = data.template_file.buildspec.rendered
  }

  vpc_config {
    security_group_ids = [data.aws_security_group.configurator_sg.id]
    subnets            = [data.aws_subnet.management_subnet.id]
    vpc_id             = data.aws_vpc.transit.id
  }
}

resource "aws_cloudwatch_log_group" "configurator" {
  name              = "/aws/codebuild/${local.configurator_name}"
  retention_in_days = 1
}
