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
        region = os.environ.get('REGION')
        instance_id = os.environ.get('INSTANCE_ID')

        if not all([region, instance_id]):
            missing = [k for k, v in {
                'REGION': region,
                'INSTANCE_ID': instance_id
            }.items() if not v]
            raise ValueError(f"Missing required environment variables: {missing}")

        logger.info(f"Updating Seafile configuration for instance ID: {instance_id}")

        # Script to update seafile.conf and manage access keys
        update_config_script = f"""#!/bin/bash

        # Exit on any error
        set -e

        # Retrieve IMDSv2 token
        TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600") || {{ echo "Failed to retrieve IMDSv2 token"; exit 1; }}

        # Set the IMDSv2 token for AWS CLI commands
        export AWS_METADATA_SERVICE_TOKEN=$TOKEN

        # Retrieve the new credentials from Parameter Store
        NEW_CREDENTIALS=$(aws ssm get-parameter --name "/seafile/iam_user/credentials" --with-decryption --region {region} --query Parameter.Value --output text) || {{ echo "Failed to retrieve new credentials"; exit 1; }}
        NEW_ACCESS_KEY_ID=$(echo $NEW_CREDENTIALS | jq -r '.access_key_id')
        NEW_SECRET_ACCESS_KEY=$(echo $NEW_CREDENTIALS | jq -r '.secret_access_key')

        # Validate that new credentials were retrieved
        if [ -z "$NEW_ACCESS_KEY_ID" ] || [ -z "$NEW_SECRET_ACCESS_KEY" ]; then
            echo "Failed to extract new credentials from Parameter Store"
            exit 1
        fi

        # Navigate to the Seafile directory
        cd /opt/seafile

        # Update seafile.conf with new credentials using sed
        sudo docker exec seafile sed -i "/\[commit_object_backend\]/,/^\[/ s/key_id = .*/key_id = $NEW_ACCESS_KEY_ID/" /opt/seafile/conf/seafile.conf || {{ echo "Failed to update commit_object_backend key_id"; exit 1; }}
        sudo docker exec seafile sed -i "/\[commit_object_backend\]/,/^\[/ s/key = .*/key = $NEW_SECRET_ACCESS_KEY/" /opt/seafile/conf/seafile.conf || {{ echo "Failed to update commit_object_backend key"; exit 1; }}
        sudo docker exec seafile sed -i "/\[fs_object_backend\]/,/^\[/ s/key_id = .*/key_id = $NEW_ACCESS_KEY_ID/" /opt/seafile/conf/seafile.conf || {{ echo "Failed to update fs_object_backend key_id"; exit 1; }}
        sudo docker exec seafile sed -i "/\[fs_object_backend\]/,/^\[/ s/key = .*/key = $NEW_SECRET_ACCESS_KEY/" /opt/seafile/conf/seafile.conf || {{ echo "Failed to update fs_object_backend key"; exit 1; }}
        sudo docker exec seafile sed -i "/\[block_backend\]/,/^\[/ s/key_id = .*/key_id = $NEW_ACCESS_KEY_ID/" /opt/seafile/conf/seafile.conf || {{ echo "Failed to update block_backend key_id"; exit 1; }}
        sudo docker exec seafile sed -i "/\[block_backend\]/,/^\[/ s/key = .*/key = $NEW_SECRET_ACCESS_KEY/" /opt/seafile/conf/seafile.conf || {{ echo "Failed to update block_backend key"; exit 1; }}

        # Restart the Docker containers
        sudo docker-compose down || {{ echo "Failed to stop Docker containers"; exit 1; }}
        sudo docker-compose up -d || {{ echo "Failed to start Docker containers"; exit 1; }}

        # Verify Seafile is running
        sudo docker-compose ps | grep seafile | grep Up || {{ echo "Seafile failed to start after restart"; exit 1; }}

        # Retrieve the old access key ID from Parameter Store
        OLD_CREDENTIALS=$(aws ssm get-parameter --name "/seafile/old_iam_user/credentials" --with-decryption --region {region} --query Parameter.Value --output text) || {{ echo "Failed to retrieve old credentials"; exit 1; }}
        OLD_ACCESS_KEY_ID=$(echo $OLD_CREDENTIALS | jq -r '.access_key_id')

        # Validate that old access key ID was retrieved
        if [ -z "$OLD_ACCESS_KEY_ID" ]; then
            echo "Failed to extract old access key ID from Parameter Store"
            exit 1
        fi

        # Delete the old access key from the IAM user
        aws iam delete-access-key --user-name seafile-service-account --access-key-id "$OLD_ACCESS_KEY_ID" --region {region} || {{ echo "Failed to delete old access key"; exit 1; }}

        echo "Seafile configuration updated and old access key deleted successfully."
        """

        # Execute the script on the EC2 instance using SSM
        response = ssm_client.send_command(
            InstanceIds=[instance_id],
            DocumentName="AWS-RunShellScript",
            Parameters={
                "commands": [
                    update_config_script
                ]
            }
        )

        command_id = response['Command']['CommandId']
        logger.info(f"SSM command sent successfully. Command ID: {command_id}")

        return {
            'statusCode': 200,
            'body': json.dumps('UpdateConfigLambda executed successfully!')
        }

    except Exception as e:
        logger.error(f"Error in UpdateConfigLambda: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f"Error: {str(e)}")
        }