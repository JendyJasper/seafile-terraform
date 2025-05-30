import boto3
import json
import time
import os
import logging

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    # Retrieve environment variables with validation
    region = os.environ.get('REGION')
    eip_public_ip = os.environ.get('EIP_PUBLIC_IP')
    commit_bucket = os.environ.get('COMMIT_BUCKET')
    fs_bucket = os.environ.get('FS_BUCKET')
    block_bucket = os.environ.get('BLOCK_BUCKET')

    if not all([region, eip_public_ip, commit_bucket, fs_bucket, block_bucket]):
        missing = [k for k, v in {
            'REGION': region,
            'EIP_PUBLIC_IP': eip_public_ip,
            'COMMIT_BUCKET': commit_bucket,
            'FS_BUCKET': fs_bucket,
            'BLOCK_BUCKET': block_bucket
        }.items() if not v]
        raise ValueError(f"Missing required environment variables: {missing}")

    ssm = boto3.client('ssm', region_name=region)
    ec2 = boto3.client('ec2', region_name=region)
    instance_id = event['detail']['instance-id']

    # Check if the instance has the SetupPending=true tag
    logger.info(f"Checking tags for instance {instance_id} in region {region}")
    tags = ec2.describe_tags(
        Filters=[
            {"Name": "resource-id", "Values": [instance_id]},
            {"Name": "key", "Values": ["SetupPending"]},
            {"Name": "value", "Values": ["true"]}
        ]
    )['Tags']
    
    if not tags:
        logger.info(f"Instance {instance_id} does not have SetupPending=true tag. Skipping.")
        return {
            'statusCode': 200,
            'body': json.dumps('Instance not targeted for setup')
        }

    logger.info(f"Starting setup for instance {instance_id}")

    # SSM command with retry logic
    script = f"""
    #!/bin/bash
    set -e  # Exit on any error

    # Install dependencies
    sudo yum update -y
    sudo yum install -y docker jq openssl python3-pip
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker ec2-user

    # Install Docker Compose
    sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    # Remove existing docker-compose link if it exists, then create a new one
    [ -e /usr/bin/docker-compose ] && sudo rm -f /usr/bin/docker-compose
    sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

    # System configuration
    sudo echo "fs.file-max=100000" >> /etc/sysctl.conf
    sudo sysctl -p

    # Set up AWS metadata token
    TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    export AWS_METADATA_SERVICE_TOKEN=$TOKEN

    # Install boto3 as ec2-user
    sudo -u ec2-user pip3 install boto3 --user

    # Create directories
    sudo mkdir -p /opt/seafile /opt/seafile-data/seafile
    cd /opt/seafile

    # Retrieve IAM user credentials for S3 access
    sudo aws ssm get-parameter --name "/seafile/iam_user/credentials" --with-decryption --region {region} --query Parameter.Value --output text > creds.json
    AWS_ACCESS_KEY_ID=$(sudo jq -r .access_key_id creds.json)
    AWS_SECRET_ACCESS_KEY=$(sudo jq -r .secret_access_key creds.json)

    # Fetch all SSM parameters upfront
    DOCKER_USERNAME=$(aws ssm get-parameter --name /seafile/docker/username --with-decryption --region {region} --query Parameter.Value --output text)
    DOCKER_PASSWORD=$(aws ssm get-parameter --name /seafile/docker/password --with-decryption --region {region} --query Parameter.Value --output text)
    MYSQL_PASSWORD=$(aws ssm get-parameter --name /seafile/mysql/password --with-decryption --region {region} --query Parameter.Value --output text)
    DB_PASSWORD=$(aws ssm get-parameter --name /seafile/db/password --with-decryption --region {region} --query Parameter.Value --output text)
    ADMIN_EMAIL=$(aws ssm get-parameter --name /seafile/admin_ui_login/username --with-decryption --region {region} --query Parameter.Value --output text)
    ADMIN_PASSWORD=$(aws ssm get-parameter --name /seafile/admin_ui_login/password --with-decryption --region {region} --query Parameter.Value --output text)

    # Log in to the correct Docker registry (docker.seadrive.org)
    echo "Attempting login to docker.seadrive.org..."
    if echo "$DOCKER_PASSWORD" | sudo docker login docker.seadrive.org --username "$DOCKER_USERNAME" --password-stdin; then
        echo "Login to docker.seadrive.org successful"
    else
        echo "Login to docker.seadrive.org failed"
        exit 1
    fi

    # Download docker-compose.yml
    sudo wget -O "docker-compose.yml" "https://manual.seafile.com/11.0/docker/docker-compose/pro/11.0/docker-compose.yml"

    # Update environment variables in docker-compose.yml with actual values
    sudo sed -i "s/MYSQL_ROOT_PASSWORD=db_dev/MYSQL_ROOT_PASSWORD=$MYSQL_PASSWORD/g" docker-compose.yml
    sudo sed -i "s/DB_ROOT_PASSWD=db_dev/DB_ROOT_PASSWD=$DB_PASSWORD/g" docker-compose.yml
    sudo sed -i "s/SEAFILE_ADMIN_EMAIL=me@example.com/SEAFILE_ADMIN_EMAIL=$ADMIN_EMAIL/g" docker-compose.yml
    sudo sed -i "s/SEAFILE_ADMIN_PASSWORD=asecret/SEAFILE_ADMIN_PASSWORD=$ADMIN_PASSWORD/g" docker-compose.yml
    sudo sed -i "s/SEAFILE_SERVER_HOSTNAME=example.seafile.com/SEAFILE_SERVER_HOSTNAME={eip_public_ip}/g" docker-compose.yml

    # Add NON_ROOT=true to the seafile service's environment
    if ! grep -A 10 'seafile:' docker-compose.yml | grep -q 'NON_ROOT=true'; then
        sudo sed -i '/environment:/a \      - NON_ROOT=true' docker-compose.yml
    fi

    # Check if redis service already exists; if not, add it before the top-level networks: section
    if ! grep -q 'redis:' docker-compose.yml; then
        sudo sed -i '/^networks:/i \  redis:\\n    image: redis:6\\n    container_name: seafile-redis\\n    networks:\\n      - seafile-net' docker-compose.yml
    fi

    # Add redis to seafile service's depends_on if not already present
    if ! grep -A 5 'depends_on:' docker-compose.yml | grep -q 'redis'; then
        sudo sed -i '/depends_on:/a \      - redis' docker-compose.yml
    fi

    # Verify the updated docker-compose.yml syntax
    sudo docker-compose -f docker-compose.yml config || (echo "Invalid docker-compose.yml syntax" && exit 1)

    # Set permissions for /opt/seafile-data/seafile/ as per documentation (Seafile 11.0.7+)
    sudo chmod -R a+rwx /opt/seafile-data/seafile/

    # Deploy Seafile
    sudo docker-compose up -d

    # Ensure seafile.conf exists before appending configurations
    sudo docker exec seafile sh -c "[ -f /opt/seafile/conf/seafile.conf ] || touch /opt/seafile/conf/seafile.conf"

    # Configure Seafile for S3 and Redis using sed to ensure proper section formatting
    # [commit_object_backend]
    if ! sudo docker exec seafile grep -q '\[commit_object_backend\]' /opt/seafile/conf/seafile.conf; then
        sudo docker exec seafile sh -c "echo '[commit_object_backend]' >> /opt/seafile/conf/seafile.conf"
        sudo docker exec seafile sh -c "echo 'name = s3' >> /opt/seafile/conf/seafile.conf"
        sudo docker exec seafile sh -c "echo 'bucket = {commit_bucket}' >> /opt/seafile/conf/seafile.conf"
        sudo docker exec seafile sh -c "echo 'key_id = $AWS_ACCESS_KEY_ID' >> /opt/seafile/conf/seafile.conf"
        sudo docker exec seafile sh -c "echo 'key = $AWS_SECRET_ACCESS_KEY' >> /opt/seafile/conf/seafile.conf"
        sudo docker exec seafile sh -c "echo 'use_v4_signature = true' >> /opt/seafile/conf/seafile.conf"
        sudo docker exec seafile sh -c "echo 'aws_region = {region}' >> /opt/seafile/conf/seafile.conf"
        # Add a blank line for readability
        sudo docker exec seafile sh -c "echo '' >> /opt/seafile/conf/seafile.conf"
    fi

    # [fs_object_backend]
    if ! sudo docker exec seafile grep -q '\[fs_object_backend\]' /opt/seafile/conf/seafile.conf; then
        sudo docker exec seafile sh -c "echo '[fs_object_backend]' >> /opt/seafile/conf/seafile.conf"
        sudo docker exec seafile sh -c "echo 'name = s3' >> /opt/seafile/conf/seafile.conf"
        sudo docker exec seafile sh -c "echo 'bucket = {fs_bucket}' >> /opt/seafile/conf/seafile.conf"
        sudo docker exec seafile sh -c "echo 'key_id = $AWS_ACCESS_KEY_ID' >> /opt/seafile/conf/seafile.conf"
        sudo docker exec seafile sh -c "echo 'key = $AWS_SECRET_ACCESS_KEY' >> /opt/seafile/conf/seafile.conf"
        sudo docker exec seafile sh -c "echo 'use_v4_signature = true' >> /opt/seafile/conf/seafile.conf"
        sudo docker exec seafile sh -c "echo 'aws_region = {region}' >> /opt/seafile/conf/seafile.conf"
        # Add a blank line for readability
        sudo docker exec seafile sh -c "echo '' >> /opt/seafile/conf/seafile.conf"
    fi

    # [block_backend]
    if ! sudo docker exec seafile grep -q '\[block_backend\]' /opt/seafile/conf/seafile.conf; then
        sudo docker exec seafile sh -c "echo '[block_backend]' >> /opt/seafile/conf/seafile.conf"
        sudo docker exec seafile sh -c "echo 'name = s3' >> /opt/seafile/conf/seafile.conf"
        sudo docker exec seafile sh -c "echo 'bucket = {block_bucket}' >> /opt/seafile/conf/seafile.conf"
        sudo docker exec seafile sh -c "echo 'key_id = $AWS_ACCESS_KEY_ID' >> /opt/seafile/conf/seafile.conf"
        sudo docker exec seafile sh -c "echo 'key = $AWS_SECRET_ACCESS_KEY' >> /opt/seafile/conf/seafile.conf"
        sudo docker exec seafile sh -c "echo 'use_v4_signature = true' >> /opt/seafile/conf/seafile.conf"
        sudo docker exec seafile sh -c "echo 'aws_region = {region}' >> /opt/seafile/conf/seafile.conf"
        # Add a blank line for readability
        sudo docker exec seafile sh -c "echo '' >> /opt/seafile/conf/seafile.conf"
    fi

    # [redis]
    if ! sudo docker exec seafile grep -q '\[redis\]' /opt/seafile/conf/seafile.conf; then
        sudo docker exec seafile sh -c "echo '[redis]' >> /opt/seafile/conf/seafile.conf"
        sudo docker exec seafile sh -c "echo 'redis_host = redis' >> /opt/seafile/conf/seafile.conf"
        sudo docker exec seafile sh -c "echo 'redis_port = 6379' >> /opt/seafile/conf/seafile.conf"
        sudo docker exec seafile sh -c "echo 'max_connections = 100' >> /opt/seafile/conf/seafile.conf"
        # Add a blank line for readability
        sudo docker exec seafile sh -c "echo '' >> /opt/seafile/conf/seafile.conf"
    fi

    # Configure boto for S3
    sudo echo '[s3]' > ~/.boto
    sudo echo 'use-sigv4 = True' >> ~/.boto
    sudo echo 'host = s3.{region}.amazonaws.com' >> ~/.boto

    # Restart services to apply NON_ROOT=true
    sudo docker-compose down
    sudo docker-compose up -d

    # Verify Seafile is running
    sudo docker-compose ps | grep seafile | grep Up || (echo "Seafile failed to start" && exit 1)
    """

    # Retry sending SSM command if instance isn't ready
    max_attempts = 10
    retry_interval = 45  # Wait 45 seconds between retries
    for attempt in range(max_attempts):
        try:
            logger.info(f"Sending SSM command to instance {instance_id} (attempt {attempt + 1}/{max_attempts})")
            response = ssm.send_command(
                InstanceIds=[instance_id],
                DocumentName='AWS-RunShellScript',
                Parameters={'commands': [script]},
                TimeoutSeconds=600
            )
            command_id = response['Command']['CommandId']
            break  # Exit loop if command is sent successfully
        except ssm.exceptions.InvalidInstanceId:
            if attempt < max_attempts - 1:
                logger.info(f"Instance {instance_id} not ready for SSM (attempt {attempt + 1}/{max_attempts}). Retrying in {retry_interval} seconds...")
                time.sleep(retry_interval)
            else:
                raise Exception(f"Failed to send SSM command to {instance_id} after {max_attempts} attempts: Instance not ready")

    # Wait for command execution result
    time.sleep(10)  # Initial wait before checking status
    result = ssm.get_command_invocation(CommandId=command_id, InstanceId=instance_id)

    max_wait = 600  # 10 minutes to account for Docker pull and setup
    waited = 10
    while result['Status'] in ['Pending', 'InProgress'] and waited < max_wait:
        logger.info(f"SSM command {command_id} status: {result['Status']}, waited {waited}/{max_wait} seconds")
        time.sleep(10)
        result = ssm.get_command_invocation(CommandId=command_id, InstanceId=instance_id)
        waited += 10

    if result['Status'] == 'Success':
        # Update tag to prevent re-triggering
        logger.info(f"Tagging instance {instance_id} as setup complete")
        ec2.create_tags(
            Resources=[instance_id],
            Tags=[{'Key': 'SetupPending', 'Value': 'false'}]
        )
        logger.info(f"Setup completed for instance {instance_id}, tag updated to SetupPending=false")
        return {
            'statusCode': 200,
            'body': json.dumps('Setup completed and tag updated')
        }
    else:
        error_message = f"Command failed with status {result['Status']}: {result.get('StandardErrorContent', 'No error details')}"
        logger.error(error_message)
        raise Exception(error_message)