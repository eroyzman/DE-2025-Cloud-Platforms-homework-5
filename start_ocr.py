import json
import boto3
import os
import urllib.parse
import botocore.exceptions

textract = boto3.client('textract')

def lambda_handler(event, context):
    try:
        # Extract bucket and key from EventBridge S3 event
        bucket = event['detail']['bucket']['name']
        key = urllib.parse.unquote_plus(event['detail']['object']['key'])
        
        print(f"Processing S3 event: Bucket={bucket}, Key={key}")
        
        # Get environment variables
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        role_arn = os.environ.get('TEXTRACT_ROLE_ARN')
        
        if not sns_topic_arn or not role_arn:
            print(f"Missing environment variables: SNS_TOPIC_ARN={sns_topic_arn}, TEXTRACT_ROLE_ARN={role_arn}")
            return {"statusCode": 400, "body": json.dumps("Missing environment variables")}
        
        # Start Textract job
        response = textract.start_document_text_detection(
            DocumentLocation={'S3Object': {'Bucket': bucket, 'Name': key}},
            NotificationChannel={'SNSTopicArn': sns_topic_arn, 'RoleArn': role_arn}
        )
        
        job_id = response['JobId']
        print(f"Started Textract job: {job_id}")
        return {"statusCode": 200, "body": json.dumps(f"Started Textract job: {job_id}")}
    
    except botocore.exceptions.ClientError as e:
        print(f"Error starting Textract job: {e}")
        return {"statusCode": 400, "body": json.dumps(f"Textract error: {str(e)}")}
    except Exception as e:
        print(f"Unexpected error: {e}")
        return {"statusCode": 500, "body": json.dumps(f"Unexpected error: {str(e)}")}