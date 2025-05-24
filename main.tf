provider "aws" {
  region = "us-east-1"
}

resource "random_id" "bucket_suffix" {
  byte_length = 6
}

resource "aws_s3_bucket" "source_bucket" {
  bucket = "pdf-source-bucket-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket" "invoice_bucket" {
  bucket = "pdf-invoice-bucket-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket" "company_data_bucket" {
  bucket = "pdf-company-data-bucket-${random_id.bucket_suffix.hex}"
}

resource "aws_sns_topic" "textract_notifications" {
  name = "textract-notifications"
}

resource "aws_iam_role" "lambda_role" {
  name = "pdf_ocr_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "textract.amazonaws.com"
          ]
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "pdf_ocr_lambda_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.source_bucket.arn,
          "${aws_s3_bucket.source_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = [
          aws_s3_bucket.invoice_bucket.arn,
          "${aws_s3_bucket.invoice_bucket.arn}/*",
          aws_s3_bucket.company_data_bucket.arn,
          "${aws_s3_bucket.company_data_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "textract:StartDocumentTextDetection",
          "textract:GetDocumentTextDetection"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = "sns:Publish"
        Resource = aws_sns_topic.textract_notifications.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_sns_topic_policy" "textract_sns_policy" {
  arn = aws_sns_topic.textract_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "textract.amazonaws.com"
        }
        Action = "sns:Publish"
        Resource = aws_sns_topic.textract_notifications.arn
      }
    ]
  })
}

resource "aws_lambda_function" "start_ocr" {
  filename      = "start_ocr.zip"
  function_name = "start_ocr"
  role          = aws_iam_role.lambda_role.arn
  handler       = "start_ocr.lambda_handler"
  runtime       = "python3.9"
  timeout       = 300

  environment {
    variables = {
      SNS_TOPIC_ARN     = aws_sns_topic.textract_notifications.arn
      TEXTRACT_ROLE_ARN = aws_iam_role.lambda_role.arn
    }
  }

  depends_on = [aws_iam_role_policy.lambda_policy]
}

resource "aws_lambda_function" "process_ocr" {
  filename      = "process_ocr.zip"
  function_name = "process_ocr"
  role          = aws_iam_role.lambda_role.arn
  handler       = "process_ocr.lambda_handler"
  runtime       = "python3.9"
  timeout       = 300

  environment {
    variables = {
      INVOICE_BUCKET      = aws_s3_bucket.invoice_bucket.bucket
      COMPANY_DATA_BUCKET = aws_s3_bucket.company_data_bucket.bucket
    }
  }

  depends_on = [aws_iam_role_policy.lambda_policy]
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_ocr.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.textract_notifications.arn
}

resource "aws_sns_topic_subscription" "process_ocr_subscription" {
  topic_arn = aws_sns_topic.textract_notifications.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.process_ocr.arn
}

resource "aws_cloudwatch_event_rule" "s3_pdf_event_rule" {
  name        = "s3_pdf_upload_rule"
  description = "Capture PDF uploads to source bucket"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.source_bucket.bucket]
      }
      object = {
        key = [{ suffix = ".pdf" }]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "start_ocr_target" {
  rule = aws_cloudwatch_event_rule.s3_pdf_event_rule.name
  arn  = aws_lambda_function.start_ocr.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_ocr.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_pdf_event_rule.arn
}

resource "aws_s3_bucket_notification" "source_bucket_notification" {
  bucket      = aws_s3_bucket.source_bucket.id
  eventbridge = true
}

output "source_bucket" {
  value = aws_s3_bucket.source_bucket.bucket
}

output "invoice_bucket" {
  value = aws_s3_bucket.invoice_bucket.bucket
}

output "company_data_bucket" {
  value = aws_s3_bucket.company_data_bucket.bucket
}