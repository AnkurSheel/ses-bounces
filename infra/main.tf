provider "aws" {
  profile = "personal"
  region  = "ap-southeast-2"
}

resource "aws_sqs_queue" "ses_bounces_queue" {
  name                      = "ses_bounces_queue"
  message_retention_seconds = 1209600
  redrive_policy            = "{\"deadLetterTargetArn\":\"${aws_sqs_queue.ses_dead_letter_queue.arn}\",\"maxReceiveCount\":4}"
}

resource "aws_sqs_queue" "ses_dead_letter_queue" {
  name = "ses_dead_letter_queue"
}

resource "aws_sns_topic" "ses_bounces_topic" {
  name = "ses_bounces_topic"
}

resource "aws_sns_topic_subscription" "ses_bounces_subscription" {
  topic_arn = aws_sns_topic.ses_bounces_topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.ses_bounces_queue.arn
}

resource "aws_ses_identity_notification_topic" "ses_bounces" {
  topic_arn                = aws_sns_topic.ses_bounces_topic.arn
  notification_type        = "Bounce"
  identity                 = "email_domain"
  include_original_headers = true
}

data "aws_iam_policy_document" "ses_bounces_queue_iam_policy" {
  policy_id = "SESBouncesQueueTopic"
  statement {
    sid       = "SESBouncesQueueTopic"
    effect    = "Allow"
    actions   = ["SQS:SendMessage"]
    resources = ["${aws_sqs_queue.ses_bounces_queue.arn}"]
    principals {
      identifiers = ["*"]
      type        = "*"
    }
    condition {
      test     = "ArnEquals"
      values   = ["${aws_sns_topic.ses_bounces_topic.arn}"]
      variable = "aws:SourceArn"
    }
  }
}

resource "aws_sqs_queue_policy" "ses_queue_policy" {
  queue_url = aws_sqs_queue.ses_bounces_queue.id
  policy    = data.aws_iam_policy_document.ses_bounces_queue_iam_policy.json
}

# -----------------------------------------------------

resource "aws_lambda_function" "SESBouncesLambda" {
  filename         = "./zips/lambda.zip"
  function_name    = "SESBouncesLambda"
  role             = aws_iam_role.ses_bounces_lambda_role.arn
  handler          = "Lambda::Lambda.Function::FunctionHandler"
  source_code_hash = filebase64sha256("./zips/lambda.zip")
  runtime          = "dotnetcore3.1"
}

data "aws_iam_policy_document" "ses_bounces_lambda_role_iam_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ses_bounces_lambda_role" {
  name               = "SESBouncesLambdaRole"
  assume_role_policy = data.aws_iam_policy_document.ses_bounces_lambda_role_iam_policy.json
}

resource "aws_iam_role_policy_attachment" "lambda_sqs_role_policy" {
  role       = aws_iam_role.ses_bounces_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}

resource "aws_lambda_event_source_mapping" "event_source_mapping" {
  event_source_arn = aws_sqs_queue.ses_bounces_queue.arn
  function_name    = aws_lambda_function.SESBouncesLambda.arn
}

