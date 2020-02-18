resource "aws_sns_topic" "router-instance-notifications" {
  name = "${var.name_prefix}-router-instance-notifications"
}

resource "aws_cloudwatch_event_rule" "router-instance-state" {
  name        = "${var.name_prefix}-router-instance-state"
  description = "Events about state changes for router instances"

  event_pattern = <<JSON
    {
      "source": [ "aws.ec2" ],
      "account": [ "${data.aws_caller_identity.me.account_id}" ],
      "region": [ "${data.aws_region.current.name}" ],
      "detail-type": [ "EC2 Instance State-change Notification" ],
      "detail": {
        "state": [ "running" ]
      }
    }
JSON
}

data "aws_iam_policy_document" "topic-policy" {
  statement {
    effect  = "Allow"
    actions = ["sns:Publish"]

    principals {
      identifiers = ["events.amazonaws.com"]
      type        = "Service"
    }

    resources = [aws_sns_topic.router-instance-notifications.arn]
  }
}

resource "aws_sns_topic_policy" "instance-notifications-policy" {
  arn    = aws_sns_topic.router-instance-notifications.arn
  policy = data.aws_iam_policy_document.topic-policy.json
}

resource "aws_cloudwatch_event_target" "router-instance-state-sns" {
  arn       = aws_sns_topic.router-instance-notifications.arn
  rule      = aws_cloudwatch_event_rule.router-instance-state.name
  target_id = "SendToSNS"
}
