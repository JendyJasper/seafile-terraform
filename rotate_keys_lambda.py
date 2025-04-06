import json
import boto3
import os
import logging

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
ssm_client = boto3.client('ssm')

def lambda_handler(event, context):
    try:
        # Get the region and instance ID from environment variables with validation
        region = os.environ.get('REGION')  # Changed from AWS_REGION to REGION
        instance_id = os.environ.get('INSTANCE_ID')

        if not all([region, instance_id]):
            missing = [k for k, v in {
                'REGION': region,  # Updated key name
                'INSTANCE_ID': instance_id
            }.items() if not v]
            raise ValueError(f"Missing required environment variables: {missing}")

        logger.info(f"Rotating keys for instance ID: {instance_id}")

        # Script to rotate IAM access keys for the seafile-service-account user
        rotate_keys_script = f"""#!/bin/bash

        # Exit on any error
        set -e

        # Retrieve IMDSv2 token
        TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600") || {{ echo "Failed to retrieve IMDSv2 token"; exit 1; }}

        # Set the IMDSv2 token for AWS CLI commands
        export AWS_METADATA_SERVICE_TOKEN=$TOKEN

        # Retrieve the current credentials from Parameter Store
        CURRENT_CREDENTIALS=$(aws ssm get-parameter --name "/seafile/iam_user/credentials" --with-decryption --region {region} --query Parameter.Value --output text) || {{ echo "Failed to retrieve current credentials"; exit 1; }}
        CURRENT_ACCESS_KEY_ID=$(echo $CURRENT_CREDENTIALS | jq -r '.access_key_id')
        CURRENT_SECRET_ACCESS_KEY=$(echo $CURRENT_CREDENTIALS | jq -r '.secret_access_key')

        # Validate that credentials were retrieved
        if [ -z "$CURRENT_ACCESS_KEY_ID" ] || [ -z "$CURRENT_SECRET_ACCESS_KEY" ]; then
            echo "Failed to extract current credentials from Parameter Store"
            exit 1
        fi

        # Generate a new access key for the seafile-service-account user
        NEW_CREDENTIALS=$(aws iam create-access-key --user-name seafile-service-account --query 'AccessKey' --output json) || {{ echo "Failed to create new access key"; exit 1; }}

        # Extract the new access key ID and secret key
        NEW_ACCESS_KEY_ID=$(echo $NEW_CREDENTIALS | jq -r '.AccessKeyId')
        NEW_SECRET_ACCESS_KEY=$(echo $NEW_CREDENTIALS | jq -r '.SecretAccessKey')

        # Store the new credentials in Parameter Store
        NEW_CREDENTIALS_JSON=$(jq -n --arg access_key_id "$NEW_ACCESS_KEY_ID" --arg secret_access_key "$NEW_SECRET_ACCESS_KEY" '{{'access_key_id': $access_key_id, 'secret_access_key': $secret_access_key}}')
        aws ssm put-parameter --name "/seafile/iam_user/credentials" --value "$NEW_CREDENTIALS_JSON" --type SecureString --overwrite --region {region} || {{ echo "Failed to store new credentials"; exit 1; }}

        # Store the old credentials (both access key ID and secret access key) in a temporary Parameter Store path
        OLD_CREDENTIALS_JSON=$(jq -n --arg access_key_id "$CURRENT_ACCESS_KEY_ID" --arg secret_access_key "$CURRENT_SECRET_ACCESS_KEY" '{{'access_key_id': $access_key_id, 'secret_access_key': $secret_access_key}}')
        aws ssm put-parameter --name "/seafile/old_iam_user/credentials" --value "$OLD_CREDENTIALS_JSON" --type SecureString --region {region} || {{ echo "Failed to store old credentials"; exit 1; }}

        echo "Key rotation completed. New access key ID: $NEW_ACCESS_KEY_ID"
        """

        # Execute the script on the EC2 instance using SSM
        response = ssm_client.send_command(
            InstanceIds=[instance_id],
            DocumentName="AWS-RunShellScript",
            Parameters={
                "commands": [
                    rotate_keys_script
                ]
            }
        )

        command_id = response['Command']['CommandId']
        logger.info(f"SSM command sent successfully. Command ID: {command_id}")

        return {
            'statusCode': 200,
            'body': json.dumps('RotateKeysLambda executed successfully!')
        }

    except Exception as e:
        logger.error(f"Error in RotateKeysLambda: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f"Error: {str(e)}")
        }