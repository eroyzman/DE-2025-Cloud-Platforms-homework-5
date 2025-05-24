import json
import boto3
import os
import botocore.exceptions

textract = boto3.client('textract')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Parse SNS message
        sns_message_raw = event['Records'][0]['Sns']['Message']
        print(f"Raw SNS message: {sns_message_raw}")
        
        try:
            sns_message = json.loads(sns_message_raw)
        except json.JSONDecodeError as e:
            print(f"Error parsing SNS message: {e}, Raw message: {sns_message_raw}")
            return {"statusCode": 400, "body": json.dumps(f"SNS parsing error: {str(e)}")}
        
        job_id = sns_message.get('JobId')
        status = sns_message.get('Status')
        
        if not job_id or not status:
            print(f"Invalid SNS message: Missing JobId or Status, Message: {sns_message}")
            return {"statusCode": 400, "body": json.dumps("Invalid SNS message")}
        
        print(f"Processing SNS event: JobId={job_id}, Status={status}")
        
        if status != "SUCCEEDED":
            print(f"Textract job {job_id} failed: {status}")
            return {"statusCode": 400, "body": json.dumps(f"Textract job failed: {status}")}
        
        # Get Textract results
        results = []
        response = textract.get_document_text_detection(JobId=job_id)
        results.append(response)
        while 'NextToken' in response:
            response = textract.get_document_text_detection(JobId=job_id, NextToken=response['NextToken'])
            results.append(response)
        
        # Extract text
        extracted_text = []
        for result in results:
            for block in result['Blocks']:
                if block['BlockType'] == 'LINE':
                    extracted_text.append(block['Text'])
        
        # Classify document
        full_text = ' '.join(extracted_text).lower()
        is_invoice = 'invoice' in full_text
        is_company_data = 'betterme' in full_text
        
        invoice_bucket = os.environ.get('INVOICE_BUCKET')
        company_data_bucket = os.environ.get('COMPANY_DATA_BUCKET')
        
        if not invoice_bucket or not company_data_bucket:
            print(f"Missing buckets: INVOICE_BUCKET={invoice_bucket}, COMPANY_DATA_BUCKET={company_data_bucket}")
            return {"statusCode": 400, "body": json.dumps("Missing bucket variables")}
        
        if is_invoice:
            output_bucket = invoice_bucket
            doc_type = 'Invoice'
        elif is_company_data:
            output_bucket = company_data_bucket
            doc_type = 'Company Data'
        else:
            output_bucket = invoice_bucket
            doc_type = 'Unclassified'
            print(f"Warning: Document does not contain 'invoice' or 'betterme', defaulting to Invoice bucket")
        
        # Save JSON
        output_key = f'output/{job_id}.json'
        output_data = {
            'job_id': job_id,
            'document_type': doc_type,
            'extracted_text': extracted_text,
            'raw_response': results
        }
        
        s3.put_object(Bucket=output_bucket, Key=output_key, Body=json.dumps(output_data, indent=2))
        print(f"Saved JSON to s3://{output_bucket}/{output_key} as {doc_type}")
        return {"statusCode": 200, "body": json.dumps(f"Saved JSON to s3://{output_bucket}/{output_key}")}
    
    except botocore.exceptions.ClientError as e:
        print(f"Error processing Textract results or saving to S3: {e}")
        return {"statusCode": 400, "body": json.dumps(f"Processing error: {str(e)}")}
    except Exception as e:
        print(f"Unexpected error: {e}")
        return {"statusCode": 500, "body": json.dumps(f"Unexpected error: {str(e)}")}