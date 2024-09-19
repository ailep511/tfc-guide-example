terraform {
required_providers {
    aws = {
    source  = "hashicorp/aws"
    version = "~>4.0"
    }
}
}

provider "aws" {}

provider "random" {}

resource "random_string" "random" {
length           = 4
special          = false
}

resource "aws_iam_role" "function_role" {
assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
    {
        Action : "sts:AssumeRole"
        Effect : "Allow"
        Sid : ""
        Principal = {
        Service = "lambda.amazonaws.com"
        }
    }
    ]
})
managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
}

# Create the function
data "archive_file" "lambda" {
type        = "zip"
source_file = "src/lambda.py"
output_path = "src/lambda.zip"
}

resource "aws_lambda_function" "test_lambda" {
function_name    = "HelloFunction-${random_string.random.id}"
role             = aws_iam_role.function_role.arn
handler          = "lambda.lambda_handler"
runtime          = "python3.9"
filename         = "src/lambda.zip"
source_code_hash = data.archive_file.lambda.output_base64sha256
}

# Explicitly create the function's log group to set retention and allow auto-cleanup
resource "aws_cloudwatch_log_group" "lambda_function_log" {
retention_in_days = 1
name              = "/aws/lambda/${aws_lambda_function.test_lambda.function_name}"
}

# Create an IAM role for the Step Functions state machine
resource "aws_iam_role" "StateMachineRole" {
name              = "StepFunctions-Terraform-Role-${random_string.random.id}"
assume_role_policy = <<Role1
{
"Version" : "2012-10-17",
"Statement" : [
    {
    "Effect" : "Allow",
    "Principal" : {
        "Service" : "states.amazonaws.com"
    },
    "Action" : "sts:AssumeRole"
    }
]
}
Role1
}

# Create an IAM policy for the Step Functions state machine
resource "aws_iam_role_policy" "StateMachinePolicy" {
role = aws_iam_role.StateMachineRole.id
policy = <<POLICY1
{
"Version" : "2012-10-17",
"Statement" : [
    {
    "Effect" : "Allow",
    "Action" : [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:CreateLogDelivery",
        "logs:GetLogDelivery",
        "logs:UpdateLogDelivery",
        "logs:DeleteLogDelivery",
        "logs:ListLogDeliveries",
        "logs:PutResourcePolicy",
        "logs:DescribeResourcePolicies",
        "logs:DescribeLogGroups",
        "cloudwatch:PutMetricData",
        "lambda:InvokeFunction"
    ],
    "Resource" : "*"
    }
]
}
POLICY1
}

# State machine definition file with the variables to replace
data "template_file" "SFDefinitionFile" {
    template = file("statemachines/statemachine.asl.json")
    vars = {
        LambdaFunction  = aws_lambda_function.test_lambda.arn                                  
    }
}

# Create the AWS Step Functions state machine
resource "aws_sfn_state_machine" "sfn_state_machine" {
    name_prefix   = "MyStateMachineViaTerraform-${random_string.random.id}"
    role_arn      = aws_iam_role.StateMachineRole.arn
    definition    = data.template_file.SFDefinitionFile.rendered
    type          = "STANDARD"
}