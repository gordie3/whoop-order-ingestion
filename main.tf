provider "aws" {
  region = var.aws_region
  access_key = var.aws_access_key_id
  secret_key = var.aws_secret_access_key

  default_tags {
    tags = {
      project = "whoop-data-ingestion"
    }
  }

}

# Secret for WHOOP
resource "aws_secretsmanager_secret" "whoop_secret" {
  name = "whoop_secret"
}

resource "random_pet" "lambda_bucket_name" {
  prefix = "whoop-data-ingestion-lambda"
  length = 4
}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket = random_pet.lambda_bucket_name.id
}

resource "aws_s3_bucket_acl" "bucket_acl" {
  bucket = aws_s3_bucket.lambda_bucket.id
  acl    = "private"
}

data "archive_file" "whoop_order_ingestion" {
  depends_on = [null_resource.install_python_dependencies]
  type       = "zip"

  source_dir  = "${path.module}/lambda_dist_pkg"
  output_path = "${path.module}/whoop-order-ingestion.zip"
}

resource "aws_s3_object" "whoop_order_ingestion" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "whoop-order-ingestion.zip"
  source = data.archive_file.whoop_order_ingestion.output_path

  etag = filemd5(data.archive_file.whoop_order_ingestion.output_path)
}

resource "aws_lambda_function" "whoop_order_ingestion" {
  depends_on    = [null_resource.install_python_dependencies]
  function_name = "WhoopOrderIngestion"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.whoop_order_ingestion.key

  runtime = "python3.9"
  handler = "handler.handler"

  source_code_hash = data.archive_file.whoop_order_ingestion.output_base64sha256

  role = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      WHOOP_CLIENT_ID          = var.whoop_client_id
      WHOOP_CLIENT_SECRET      = var.whoop_client_secret
      WHOOP_SECRET_ID          = aws_secretsmanager_secret.whoop_secret.id
      DAILY_TRACKING_DB        = var.daily_tracking_db
      NOTION_INTEGRATION_TOKEN = var.notion_integration_token
    }
  }
}

resource "aws_cloudwatch_log_group" "whoop_order_ingestion" {
  name = "/aws/lambda/${aws_lambda_function.whoop_order_ingestion.function_name}"

  retention_in_days = 30
}

resource "aws_iam_role" "lambda_exec" {
  name = "serverless_lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "secrets_manager" {
  name = "whoop_secret_manager_access"
  role = aws_iam_role.lambda_exec.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        "Effect": "Allow",
        "Action": "secretsmanager:GetSecretValue",
        "Resource": aws_secretsmanager_secret.whoop_secret.arn
      },
    ]
  })
}

resource "aws_apigatewayv2_api" "lambda" {
  name          = "serverless_lambda_gw"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.lambda.id

  name        = "serverless_lambda_stage"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_apigatewayv2_integration" "whoop_order_ingestion" {
  api_id = aws_apigatewayv2_api.lambda.id

  integration_uri    = aws_lambda_function.whoop_order_ingestion.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "whoop_order_ingestion" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key = "POST /event"
  target    = "integrations/${aws_apigatewayv2_integration.whoop_order_ingestion.id}"
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.lambda.name}"

  retention_in_days = 30
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.whoop_order_ingestion.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}

#################
# Rotation Lambda
#################

resource "aws_s3_object" "whoop_secret_rotation" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "whoop-secret-ratation.zip"
  source = data.archive_file.whoop_order_ingestion.output_path

  etag = filemd5(data.archive_file.whoop_order_ingestion.output_path)
}

resource "aws_lambda_function" "whoop_secret_rotation" {
  depends_on    = [null_resource.install_python_dependencies]
  function_name = "WhoopSecretRotation"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.whoop_secret_rotation.key

  runtime = "python3.9"
  handler = "handler.rotate_secret"

  source_code_hash = data.archive_file.whoop_order_ingestion.output_base64sha256

  role = aws_iam_role.lambda_rotate_exec.arn

  environment {
    variables = {
      WHOOP_CLIENT_ID          = var.whoop_client_id
      WHOOP_CLIENT_SECRET      = var.whoop_client_secret
      WHOOP_SECRET_ID          = aws_secretsmanager_secret.whoop_secret.id
      DAILY_TRACKING_DB        = var.daily_tracking_db
      NOTION_INTEGRATION_TOKEN = var.notion_integration_token
    }
  }
}

resource "aws_cloudwatch_log_group" "whoop_secret_rotation" {
  name = "/aws/lambda/${aws_lambda_function.whoop_secret_rotation.function_name}"

  retention_in_days = 30
}

resource "aws_iam_role" "lambda_rotate_exec" {
  name = "whoop_secret_rotation_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rotate_lambda_policy" {
  role       = aws_iam_role.lambda_rotate_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "rotate_secrets_manager" {
  name = "whoop_secret_rotate_access"
  role = aws_iam_role.lambda_rotate_exec.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        "Effect": "Allow",
        "Action": [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
        ],
        "Resource": aws_secretsmanager_secret.whoop_secret.arn
      },
    ]
  })
}

resource "aws_cloudwatch_event_rule" "whoop_secret_rotation_schedule" {
    name = "whoop_secret_rotation_schedule"
    description = "Schedule for Whoop secret rotation Function"
    schedule_expression = "rate(45 minutes)"
}

resource "aws_cloudwatch_event_target" "whoop_secret_rotation_schedule_lambda" {
    rule = aws_cloudwatch_event_rule.whoop_secret_rotation_schedule.name
    target_id = "whoop_secret_rotation"
    arn = aws_lambda_function.whoop_secret_rotation.arn
}


resource "aws_lambda_permission" "allow_events_bridge_to_run_lambda" {
    statement_id = "AllowExecutionFromCloudWatch"
    action = "lambda:InvokeFunction"
    function_name = aws_lambda_function.whoop_secret_rotation.function_name
    principal = "events.amazonaws.com"
}
