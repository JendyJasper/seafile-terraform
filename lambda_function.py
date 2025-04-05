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
    sudo yum update -y
    sudo yum install -y docker jq openssl python3-pip
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker ec2-user
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
    sudo echo "fs.file-max=100000" >> /etc/sysctl.conf
    sudo sysctl -p
    TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    export AWS_METADATA_SERVICE_TOKEN=$TOKEN
    sudo pip3 install boto3
    sudo mkdir -p /opt/seafile
    cd /opt/seafile
    sudo aws ssm get-parameter --name "/seafile/iam_user/credentials" --with-decryption --region {region} --query Parameter.Value --output text > creds.json
    AWS_ACCESS_KEY_ID=$(sudo jq -r .access_key_id creds.json)
    AWS_SECRET_ACCESS_KEY=$(sudo jq -r .secret_access_key creds.json)
    sudo docker login -u "$(aws ssm get-parameter --name /seafile/docker/username --with-decryption --region {region} --query Parameter.Value --output text)" \
                      -p "$(aws ssm get-parameter --name /seafile/docker/password --with-decryption --region {region} --query Parameter.Value --output text)"
    sudo wget -O "docker-compose.yml" "https://manual.seafile.com/11.0/docker/docker-compose/pro/11.0/docker-compose.yml"
    sudo sed -i 's/- MYSQL_ROOT_PASSWORD=db_dev/- MYSQL_ROOT_PASSWORD=$(aws ssm get-parameter --name \/seafile\/mysql\/password --with-decryption --region {region} --query Parameter.Value --output text | tr -d "\\n")/g' docker-compose.yml
    sudo sed -i 's/- DB_ROOT_PASSWD=db_dev/- DB_ROOT_PASSWD=$(aws ssm get-parameter --name \/seafile\/db\/password --with-decryption --region {region} --query Parameter.Value --output text | tr -d "\\n")/g' docker-compose.yml
    sudo sed -i 's/- SEAFILE_ADMIN_EMAIL=me@example.com/- SEAFILE_ADMIN_EMAIL=$(aws ssm get-parameter --name \/seafile\/admin_ui_login\/username --with-decryption --region {region} --query Parameter.Value --output text | tr -d "\\n")/g' docker-compose.yml
    sudo sed -i 's/- SEAFILE_ADMIN_PASSWORD=asecret/- SEAFILE_ADMIN_PASSWORD=$(aws ssm get-parameter --name \/seafile\/admin_ui_login\/password --with-decryption --region {region} --query Parameter.Value --output text | tr -d "\\n")/g' docker-compose.yml
    sudo sed -i 's/- SEAFILE_SERVER_HOSTNAME=example.seafile.com/- SEAFILE_SERVER_HOSTNAME={eip_public_ip}/g' docker-compose.yml
    sudo sed -i '/networks:/i \  redis:\\n    image: redis:6\\n    container_name: seafile-redis\\n    networks:\\n      - seafile-net' docker-compose.yml
    sudo mkdir -p /opt/seafile-data/seafile
    sudo chown -R 1000:1000 /opt/seafile-data
    sudo docker-compose up -d
    sudo docker exec seafile sh -c "if ! grep -q '[commit_object_backend]' /opt/seafile-data/seafile/seafile.conf; then echo '[commit_object_backend]' >> /opt/seafile-data/seafile/seafile.conf; fi"
    sudo docker exec seafile sh -c "if ! grep -q 'name = s3' /opt/seafile-data/seafile/seafile.conf; then echo 'name = s3' >> /opt/seafile-data/seafile/seafile.conf; fi"
    sudo docker exec seafile sh -c "if ! grep -q 'bucket = {commit_bucket}' /opt/seafile-data/seafile/seafile.conf; then echo 'bucket = {commit_bucket}' >> /opt/seafile-data/seafile/seafile.conf; fi"
    sudo docker exec seafile sh -c "if ! grep -q 'key_id = ' /opt/seafile-data/seafile/seafile.conf; then echo 'key_id = '$AWS_ACCESS_KEY_ID >> /opt/seafile-data/seafile/seafile.conf; fi"
    sudo docker exec seafile sh -c "if ! grep -q 'key = ' /opt/seafile-data/seafile/seafile.conf; then echo 'key = '$AWS_SECRET_ACCESS_KEY >> /opt/seafile-data/seafile/seafile.conf; fi"
    sudo docker exec seafile sh -c "if ! grep -q 'use_v4_signature = true' /opt/seafile-data/seafile/seafile.conf; then echo 'use_v4_signature = true' >> /opt/seafile-data/seafile/seafile.conf; fi"
    sudo docker exec seafile sh -c "if ! grep -q 'aws_region = {region}' /opt/seafile-data/seafile/seafile.conf; then echo 'aws_region = {region}' >> /opt/seafile-data/seafile/seafile.conf; fi"
    sudo docker exec seafile sh -c "if ! grep -q '[fs_object_backend]' /opt/seafile-data/seafile/seafile.conf; then echo '[fs_object_backend]' >> /opt/seafile-data/seafile/seafile.conf; fi"
    sudo docker exec seafile sh -c "if ! grep -q 'bucket = {fs_bucket}' /opt/seafile-data/seafile/seafile.conf; then echo 'bucket = {fs_bucket}' >> /opt/seafile-data/seafile/seafile.conf; fi"
    sudo docker exec seafile sh -c "if ! grep -q '[block_backend]' /opt/seafile-data/seafile/seafile.conf; then echo '[block_backend]' >> /opt/seafile-data/seafile/seafile.conf; fi"
    sudo docker exec seafile sh -c "if ! grep -q 'bucket = {block_bucket}' /opt/seafile-data/seafile/seafile.conf; then echo 'bucket = {block_bucket}' >> /opt/seafile-data/seafile/seafile.conf; fi"
    sudo docker exec seafile sh -c "if ! grep -q '[redis]' /opt/seafile-data/seafile/seafile.conf; then echo '[redis]' >> /opt/seafile-data/seafile/seafile.conf; fi"
    sudo docker exec seafile sh -c "if ! grep -q 'redis_host = redis' /opt/seafile-data/seafile/seafile.conf; then echo 'redis_host = redis' >> /opt/seafile-data/seafile/seafile.conf; fi"
    sudo docker exec seafile sh -c "if ! grep -q 'redis_port = 6379' /opt/seafile-data/seafile/seafile.conf; then echo 'redis_port = 6379' >> /opt/seafile-data/seafile/seafile.conf; fi"
    sudo docker exec seafile sh -c "if ! grep -q 'max_connections = 100' /opt/seafile-data/seafile/seafile.conf; then echo 'max_connections = 100' >> /opt/seafile-data/seafile/seafile.conf; fi"
    sudo echo '[s3]' > ~/.boto
    sudo echo 'use-sigv4 = True' >> ~/.boto
    sudo echo 'host = s3.{region}.amazonaws.com' >> ~/.boto
    sudo docker-compose restart seafile
    sudo docker-compose restart redis
    sudo docker-compose ps | grep seafile | grep Up || (echo "Seafile failed to start" && exit 1)
    """

    # Retry sending SSM command if instance isn't ready
    max_attempts = 5
    retry_interval = 30  # Wait 30 seconds between retries
    for attempt in range(max_attempts):
        try:
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

    max_wait = 300
    waited = 10
    while result['Status'] in ['Pending', 'InProgress'] and waited < max_wait:
        time.sleep(10)
        result = ssm.get_command_invocation(CommandId=command_id, InstanceId=instance_id)
        waited += 10

    if result['Status'] == 'Success':
        # Update tag to prevent re-triggering
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
        raise Exception(f"Command failed with status {result['Status']}: {result.get('StandardErrorContent', 'No error details')}")