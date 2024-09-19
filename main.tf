terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

variable "email" {
  type        = string
  description = "A valid email that will be subscribed to the SNS topic for approval or deny notifications"
  validation {
    condition     = can(regex("^(.+)@(\\S+)$", var.email))
    error_message = "Must be a valid email address."
  }
}

resource "aws_sfn_state_machine" "new_account_application" {
  name     = "NewAccountApplicationStateMachine"
  role_arn = aws_iam_role.state_machine_role.arn

  definition = templatefile("statemachine/application_service.asl.json", {
    CheckIdentityFunctionArn            = aws_lambda_function.check_identity.arn
    CheckAddressFunctionArn             = aws_lambda_function.check_address.arn
    AccountsTable                       = aws_dynamodb_table.accounts.name
    SendCustomerNotificationSNSTopicArn = aws_sns_topic.send_customer_notification.arn
    HomeInsuranceInterestQueueArn       = aws_sqs_queue.home_insurance_interest.arn
  })
}

resource "aws_iam_role" "state_machine_role" {
  name = "NewAccountApplicationStateMachineRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "state_machine_policy" {
  policy_arn = aws_iam_policy.state_machine_policy.arn
  role       = aws_iam_role.state_machine_role.name
}

resource "aws_iam_policy" "state_machine_policy" {
  name = "NewAccountApplicationStateMachinePolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.check_identity.arn,
          aws_lambda_function.check_address.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.accounts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.send_customer_notification.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.home_insurance_interest.arn
      }
    ]
  })
}

resource "aws_lambda_function" "check_identity" {
  filename      = "functions/check-identity/app.zip"
  function_name = "CheckIdentityFunction"
  role          = aws_iam_role.lambda_role.arn
  handler       = "app.lambdaHandler"
  runtime       = "nodejs14.x"

  source_code_hash = filebase64sha256("functions/check-identity/app.zip")
}

resource "aws_cloudwatch_log_group" "check_identity" {
  name              = "/aws/lambda/${aws_lambda_function.check_identity.function_name}"
  retention_in_days = 7
}

resource "aws_lambda_function" "check_address" {
  filename      = "functions/check-address/app.zip"
  function_name = "CheckAddressFunction"
  role          = aws_iam_role.lambda_role.arn
  handler       = "app.lambdaHandler"
  runtime       = "nodejs14.x"

  source_code_hash = filebase64sha256("functions/check-address/app.zip")
}

resource "aws_cloudwatch_log_group" "check_address" {
  name              = "/aws/lambda/${aws_lambda_function.check_address.function_name}"
  retention_in_days = 7
}

resource "aws_iam_role" "lambda_role" {
  name = "LambdaFunctionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

resource "aws_dynamodb_table" "accounts" {
  name           = "AccountsTable"
  billing_mode   = "PROVISIONED"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "email"

  attribute {
    name = "email"
    type = "S"
  }
}

resource "aws_sns_topic" "send_customer_notification" {
  name = "SendCustomerNotificationSNSTopic"
}

resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.send_customer_notification.arn
  protocol  = "email"
  endpoint  = var.email
}

resource "aws_sqs_queue" "home_insurance_interest" {
  name = "HomeInsuranceInterestQueue"
}

output "new_account_application_state_machine_arn" {
  description = "New Account Application State Machine ARN"
  value       = aws_sfn_state_machine.new_account_application.arn
}
