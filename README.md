The solution involves copying PDFs from a source storage to an S3 bucket, where they are processed:

PDFs land in a source S3 bucket, triggering an EventBridge rule.

A Lambda function starts a Textract OCR job, with completion notifications sent via SNS.

Another Lambda function retrieves OCR results, classifies the document, and saves JSON to either an Invoice or Company Data S3 bucket.

how to run:

terraform init

terraform apply
