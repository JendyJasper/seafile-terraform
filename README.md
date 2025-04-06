# Seafile Deployment on AWS with Terraform and Lambda

## Overview

This repository automates the deployment of a Seafile Pro server on an AWS EC2 instance using Terraform for infrastructure provisioning and an AWS Lambda function for configuration. Seafile is a file synchronization and collaboration platform, and this project sets it up to use AWS S3 for storage and Redis for caching, ensuring a scalable and secure deployment.

The deployment process involves:

* **Terraform**: Provisions the necessary AWS infrastructure (VPC, EC2 instance, S3 buckets, Lambda function, etc.).
* **AWS Lambda**: Configures the EC2 instance by installing Docker, pulling the Seafile Pro image, and setting up the Seafile configuration.
* **GitHub Actions**: Automates the Terraform deployment and destruction workflows.
* **OIDC Integration**: Uses OpenID Connect (OIDC) to allow GitHub Actions to assume an AWS role for Terraform execution.

### Key Features

* **Infrastructure as Code**: Uses Terraform to provision AWS resources, including VPC, EC2, S3 buckets, and Lambda.
* **Automated Configuration**: A Lambda function configures the EC2 instance with Seafile, using Docker Compose.
* **S3 Integration**: Configures Seafile to use AWS S3 for storing commit objects, file system objects, and block data.
* **Redis Caching**: Integrates Redis for improved performance.
* **Non-Root User**: Runs Seafile as a non-root user inside the container for better security (Seafile 11.0+).
* **CI/CD with GitHub Actions**: Automates deployment and destruction of infrastructure.
* **Secure Credential Management**: Stores sensitive credentials in AWS SSM Parameter Store and GitHub Secrets.

## Repository Structure

* `.github/workflows/terraform.yml`: GitHub Actions workflow for Terraform deployment.
* `.github/workflows/destroy.yml`: GitHub Actions workflow for Terraform destruction.
* `data.tf`: Terraform data sources for fetching the AWS account ID and Amazon Linux 2 AMI.
* `ec2.tf`: Terraform configuration for the EC2 instance, security groups, and Elastic IP.
* `lambda_function.py`: AWS Lambda function script for `SetupEC2Lambda` to configure the EC2 instance with Seafile.
* `locals.tf`: Local variables for Seafile S3 buckets and SSM parameters.
* `main.tf`: Main Terraform configuration for provisioning AWS resources.
* `outputs.tf`: Terraform outputs for the Seafile Elastic IP and S3 bucket names.
* `rotate_keys_lambda.py`: AWS Lambda function script for `RotateKeysLambda` to rotate IAM access keys.
* `rotate_keys_lambda.tf`: Terraform configuration for the `RotateKeysLambda` function and its EventBridge schedule.
* `s3.tf`: Terraform configuration for S3 buckets used by Seafile.
* `setup_lambda.tf`: Terraform configuration for the `SetupEC2Lambda` function and its EventBridge trigger.
* `update_config_lambda.py`: AWS Lambda function script for `UpdateConfigLambda` to update `seafile.conf` with new IAM credentials.
* `update_config_lambda.tf`: Terraform configuration for the `UpdateConfigLambda` function and its EventBridge trigger on Parameter Store changes.
* `variables.tf`: Terraform variables for region, instance type, and sensitive credentials.
* `vpc.tf`: Terraform configuration for the VPC and networking resources.

## Prerequisites

Before using this repository, ensure you have the following:

* **AWS Account** with permissions to:
  * Create and manage EC2 instances, VPCs, S3 buckets, Lambda functions, IAM roles, and SSM parameters.
  * Set up OIDC identity providers.
* **GitHub Account**:
  * A GitHub repository for storing the code.
  * GitHub Actions enabled for CI/CD.
* **Terraform**:
  * Installed locally if running Terraform manually (version 1.11.3).
* **Docker Hub Credentials**:
  * Seafile provides default credentials for evaluation purposes at [https://customer.seafile.com/downloads/](https://customer.seafile.com/downloads/). You can use these credentials.

## Setup Instructions

### Step 1: Clone the Public Repository

1. **Clone the Repository**:
   * Use the `git clone` command to download a copy of this repository to your local machine:
     ```bash
     git clone https://github.com/JendyJasper/seafile-terraform.git
     ```
   * This creates a directory named `seafile-terraform` containing the repository files.

2. **Navigate to the Repository Directory**:
   * Change into the cloned repository’s directory:
     ```bash
     cd seafile-terraform
     ```

### Step 2: Create Your Own GitHub Repository

1. **Create a New Repository on GitHub**:
   * Log in to your GitHub account.
   * Click the **+** icon in the top-right corner and select **New repository**.
   * Name it (e.g., `seafile-deployment`), choose visibility (public or private), and **do not initialize it with a README** (since you’ll be pushing an existing repository).
   * Click **Create repository** and note the repository URL (e.g., `https://github.com/<your-username>/seafile-deployment.git`).

### Step 3: Push the Cloned Repository to Your GitHub Account

1. **Update the Remote URL**:
   * Replace the original repository’s remote URL with your new GitHub repository URL:
     ```bash
     git remote set-url origin https://github.com/<your-username>/seafile-deployment.git
     ```
   * Replace `<your-username>` with your actual GitHub username.

2. **Verify the Remote** (Optional):
   * Check that the remote URL has been updated correctly:
     ```bash
     git remote -v
     ```

3. **Push to Your Repository**:
   * Push the cloned repository to your GitHub account. Assuming the default branch is `main`:
     ```bash
     git push origin main
     ```
   * If the default branch is `master` (check with `git branch`), use `git push origin master` instead.
   * You may be prompted to authenticate with your GitHub credentials. If using a personal access token (required for HTTPS since August 2021), enter it when prompted.

### Notes
- **Authentication**: Ensure your Git client is configured with your GitHub credentials. You can set this up globally with:
  ```bash
  git config --global user.name "Your Name"
  git config --global user.email "your-email@example.com"

### 2. Set Up OIDC for GitHub Actions

To allow GitHub Actions to interact with AWS, you need to set up an OIDC identity provider and an IAM role.

#### Step 1: Create an OIDC Identity Provider in AWS

1. **Log in to the AWS Management Console**:
   * Navigate to the **IAM** service.

2. **Add an Identity Provider**:
   * Go to **Identity Providers** in the left sidebar and click **Add provider**.
   * Select **OpenID Connect** as the provider type.
   * For **Provider URL**, enter: `https://token.actions.githubusercontent.com`.
   * Click **Get thumbprint** to automatically fetch the thumbprint.
   * For **Audience**, enter: `sts.amazonaws.com`.
   * Click **Add provider**.

#### Step 2: Create the TerraformExecutionRole IAM Role

1. **Create the Role**:
   * In the IAM console, go to **Roles** and click **Create role**.
   * Select **Web identity** as the trusted entity type.
   * Choose the OIDC provider you created (`token.actions.githubusercontent.com`).
   * For **Audience**, select `sts.amazonaws.com`.
   * Click **Next**.

2. **Attach a Policy**:
   * Click **Create policy** to create a new policy named `TerraformManageResourcesPolicy`.
   * Use the JSON editor and paste the following policy (adjust the account ID and region as needed):
     
   ```json
   {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["ec2:*"],
            "Resource": [
                "arn:aws:ec2:<region>:<account-id>:*",
                "arn:aws:ec2:<region>::image/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": ["ec2:Describe*", "ec2:DescribeImages"],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": ["s3:*"],
            "Resource": [
                "arn:aws:s3:::seafile-storage-bucket-*",
                "arn:aws:s3:::seafile-<region>-*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:CreateBucket",
                "s3:PutBucketVersioning",
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket",
                "s3:GetReplicationConfiguration",
                "s3:GetEncryptionConfiguration"
            ],
            "Resource": [
                "arn:aws:s3:::seafile-<region>-*",
                "arn:aws:s3:::seafile-<region>-*/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:CreateTable",
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:DeleteItem"
            ],
            "Resource": "arn:aws:dynamodb:<region>:<account-id>:table/seafile-terraform-locks"
        },
        {
            "Effect": "Allow",
            "Action": ["iam:*"],
            "Resource": [
                "arn:aws:iam::<account-id>:role/SeafileEC2Role",
                "arn:aws:iam::<account-id>:policy/SeafileS3AndSSMAccessPolicy",
                "arn:aws:iam::<account-id>:policy/SeafileServiceAccountS3Policy",
                "arn:aws:iam::<account-id>:instance-profile/seafile-instance-profile",
                "arn:aws:iam::<account-id>:user/seafile-service-account",
                "arn:aws:iam::<account-id>:role/SeafileLambdaExecutionRole",
                "arn:aws:iam::<account-id>:policy/SeafileLambdaPolicy",
                "arn:aws:iam::<account-id>:policy/RotateKeysLambdaPolicy",
                "arn:aws:iam::<account-id>:role/RotateKeysLambdaExecutionRole",
                "arn:aws:iam::<account-id>:policy/UpdateConfigLambdaPolicy",
                "arn:aws:iam::<account-id>:role/UpdateConfigLambdaExecutionRole"
            ]
        },
        {
            "Effect": "Allow",
            "Action": ["ssm:*"],
            "Resource": "arn:aws:ssm:<region>:<account-id>:parameter/seafile/*"
        },
        {
            "Effect": "Allow",
            "Action": ["ssm:GetParameter", "ssm:GetParameters", "ssm:ListTagsForResource"],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": "ssm:DescribeParameters",
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": ["lambda:*"],
            "Resource": [
                "arn:aws:lambda:<region>:<account-id>:function:SetupEC2Lambda",
                "arn:aws:lambda:<region>:<account-id>:function:RotateKeysLambda",
                "arn:aws:lambda:<region>:<account-id>:function:UpdateConfigLambda"
            ]
        },
        {
            "Effect": "Allow",
            "Action": ["events:*"],
            "Resource": [
                "arn:aws:events:<region>:<account-id>:rule/SeafileSetupRule",
                "arn:aws:events:<region>:<account-id>:rule/RotateKeysSchedule",
                "arn:aws:events:<region>:<account-id>:rule/ParameterStoreChangeRule"
            ]
        },
        {
            "Effect": "Allow",
            "Action": ["logs:*"],
            "Resource": "arn:aws:logs:<region>:<account-id>:*"
        }
    ]
   }

* Replace `<region>` with your AWS region (e.g., `ap-southeast-1`) and `<account-id>` with your AWS account ID.
   * Click **Next**, name the policy `TerraformManageResourcesPolicy`, and click **Create policy**.
   * Back in the role creation wizard, attach the `TerraformManageResourcesPolicy` policy to the role.
   * Click **Next**.

3. **Add a Trust Policy Condition**:
   * Before finalizing the role, click **Edit** on the trust relationship and add a condition to allow all branches in your GitHub repository:
     ```json
     {
         "Version": "2012-10-17",
         "Statement": [
             {
                 "Effect": "Allow",
                 "Principal": {
                     "Federated": "arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com"
                 },
                 "Action": "sts:AssumeRoleWithWebIdentity",
                 "Condition": {
                     "StringEquals": {
                         "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                     },
                     "StringLike": {
                         "token.actions.githubusercontent.com:sub": "repo:<your-username>/seafile-deployment:*"
                     }
                 }
             }
         ]
     }
     ```
   * Replace `<account-id>` with your AWS account ID and `<your-username>` with your GitHub username.
   * Click **Update**.

4. **Finalize the Role**:
   * Name the role `TerraformExecutionRole`.
   * Click **Create role**.

#### Step 3: Note the Role ARN

* After creating the role, note its ARN (e.g., `arn:aws:iam::<account-id>:role/TerraformExecutionRole`). You’ll need this for GitHub Secrets.

### 3. Configure GitHub Secrets

In your GitHub repository (`seafile-deployment`), add the following secrets under **Settings > Secrets and variables > Actions > Secrets**:

| Secret Name            | Description                              | Example Value             |
|------------------------|------------------------------------------|---------------------------|
| AWS_ACCOUNT_ID         | Your AWS account ID                      | 123456789012              |
| AWS_REGION             | AWS region                               | ap-southeast-1            |
| BACKEND_BUCKET_SUFFIX  | Suffix for Terraform backend bucket      | randomsuffix123           |
| BACKEND_DYNAMODB_TABLE | DynamoDB table for Terraform locks       | seafile-terraform-locks   |
| ADMIN_UI_USERNAME      | Seafile admin username                   | admin@example.com         |
| ADMIN_UI_PASSWORD      | Seafile admin password                   | your-admin-password       |
| DB_USERNAME            | Seafile database username                | seafile                   |
| DB_PASSWORD            | Seafile database password                | your-db-password          |
| MYSQL_USERNAME         | MySQL root username                      | seafile                   |
| MYSQL_PASSWORD         | MySQL root password                      | your-db-password          |
| DOCKER_USERNAME        | Docker Hub username                      | Use default from Seafile  |
| DOCKER_PASSWORD        | Docker Hub password                      | Use default from Seafile  |

> **Note**: For the `BACKEND_BUCKET_SUFFIX`, use a random, unique value (at least 8 characters long) to ensure the S3 bucket name is globally unique. For example, `randomsuffix123` Also, MYSQL_PASSWORD and av has to be the same value.

### 4. Deploy the Infrastructure

#### Option 1: Using GitHub Actions (Recommended)

1. **Push to Any Branch**:
   * The `terraform.yml` workflow triggers on pushes to any branch. For example, push to the `main` branch:
     
     ```git push origin main```
     
   * This triggers the `terraform.yml` workflow, which will:
     * Set up the Terraform backend (S3 bucket and DynamoDB table).
     * Run `terraform init`, `terraform plan`, and `terraform apply`.

2. **Monitor the Workflow**:
   * Go to the **Actions** tab in your GitHub repository to monitor the workflow.
   * If successful, the infrastructure will be deployed, and the Lambda function will configure the EC2 instance.

3. **Retrieve Outputs**:
   * After the workflow completes, check the workflow logs for the Terraform outputs:
     * `seafile_elastic_ip`: The public IP to access Seafile.
     * `seafile_s3_buckets`: The names of the S3 buckets created for Seafile.

#### Option 2: Manual Deployment with Terraform

1. **Install Terraform**:
   * Install Terraform (version 1.11.3) on your local machine.

2. **Set Up AWS Credentials**:
   * Configure your AWS credentials using the AWS CLI:
     `aws configure`

3. **Update the Backend Configuration**:
   * In `main.tf`, update the backend `"s3"` block with your values:
     ```hcl
     terraform {
       backend "s3" {
         bucket         = "seafile-<region>-<suffix>"
         key            = "seafile-terraform/terraform.tfstate"
         region         = "<region>"
         dynamodb_table = "seafile-terraform-locks"
       }
     }
    
    * Replace `<region>` with your AWS region and `<suffix>` with a unique value (e.g., `randomsuffix123`).

4. **Set Sensitive Variables as Environment Variables**:
   * Instead of using a `terraform.tfvars` file for sensitive values, set them as environment variables to avoid storing secrets in plain text. For example:
     ```bash
     export TF_VAR_region="<region>"
     export TF_VAR_admin_ui_username="<admin-username>"
     export TF_VAR_admin_ui_password="<admin-password>"
     export TF_VAR_db_username="<db-username>"
     export TF_VAR_db_password="<db-password>"
     export TF_VAR_mysql_username="<db-username>"  # Must be the same as db_username
     export TF_VAR_mysql_password="<db-password>"  # Must be the same as db_password
     export TF_VAR_docker_username="<docker-username>"
     export TF_VAR_docker_password="<docker-password>"
     ```
   * Replace the placeholder values with your own.

   > **Warning**: While environment variables are safer than storing secrets in a `terraform.tfvars` file, they can still be exposed in logs or shell history. For production use, consider using a secrets management tool like AWS Secrets Manager or HashiCorp Vault to securely inject these values.

5. **Run Terraform Commands**:
   * Initialize Terraform:
     ```bash
     terraform init
     ```
   * Run Terraform plan and apply:
     ```bash
     terraform plan
     terraform apply -auto-approve
     ```

6. **Retrieve Outputs**:
   * After deployment, Terraform will output:
     * `seafile_elastic_ip`: The public IP to access Seafile.
     * `seafile_s3_buckets`: The names of the S3 buckets created for Seafile.

### 5. Access Seafile

* Access Seafile at `http://<seafile_elastic_ip>`.
* Log in with the admin credentials specified in GitHub Secrets (`ADMIN_UI_USERNAME` and `ADMIN_UI_PASSWORD`).

## SSM Parameter Store Paths

The following AWS SSM Parameter Store paths are used to store sensitive credentials and configuration values. These parameters are created by Terraform and accessed by the Lambda function during deployment. You can retrieve them from the AWS SSM Parameter Store in the AWS Console or via the AWS CLI.

| Parameter Path                    | Description                                      |
|-----------------------------------|--------------------------------------------------|
| `/seafile/iam_user/credentials`   | IAM credentials for the Seafile service account  |
| `/seafile/ec2/keypair`            | Private key for the Seafile EC2 instance         |
| `/seafile/admin_ui_login/username`| Username for Seafile admin UI login              |
| `/seafile/admin_ui_login/password`| Password for Seafile admin UI login              |
| `/seafile/db/username`            | Username for Seafile database                    |
| `/seafile/db/password`            | Password for Seafile database                    |
| `/seafile/mysql/username`         | Username for MySQL database                      |
| `/seafile/mysql/password`         | Password for MySQL database                      |
| `/seafile/docker/username`        | Username for Docker login                        |
| `/seafile/docker/password`        | Password for Docker login                        |
| `/seafile/old_iam_user/credentials`| Old IAM credentials (temporary during rotation)

To retrieve a parameter using the AWS CLI, for example:

```bash
aws ssm get-parameter --name "/seafile/admin_ui_login/username" --with-decryption --region <region>
```

## Expected Configuration in seafile.conf

The Lambda function configures `/opt/seafile/conf/seafile.conf` inside the Seafile container with the following sections for S3 and Redis:

```ini
[commit_object_backend]
name = s3
bucket = <commit-bucket-name>
key_id = <aws-access-key-id>
key = <aws-secret-access-key>
use_v4_signature = true
aws_region = <region>

[fs_object_backend]
name = s3
bucket = <fs-bucket-name>
key_id = <aws-access-key-id>
key = <aws-secret-access-key>
use_v4_signature = true
aws_region = <region>

[block_backend]
name = s3
bucket = <block-bucket-name>
key_id = <aws-access-key-id>
key = <aws-secret-access-key>
use_v4_signature = true
aws_region = <region>

[redis]
redis_host = redis
redis_port = 6379
max_connections = 100
```
## Destroying the Infrastructure

To destroy the infrastructure:

1. **Using GitHub Actions**:
   * Go to the **Actions** tab in your GitHub repository.
   * Select the Terraform Destroy workflow and click **Run workflow**.
   * This will run `terraform destroy` to remove all resources.

2. **Manually with Terraform**:
   * Run:
     ```bash
     terraform destroy -auto-approve
     ```

## Troubleshooting

### Common Issues

1. **502 Bad Gateway Error**:
   * **Cause**: Seafile failed to start.
   * **Solution**: Check the Seafile container logs:
     ```bash
     docker logs seafile
     ```
     Ensure the `/opt/seafile-data/seafile/` directory has the correct permissions (`chmod -R a+rwx /opt/seafile-data/seafile/`).

2. **MySQL Aborted Connection Errors**:
   * **Cause**: Seafile failed to start, causing connection issues with MySQL.
   * **Solution**: Fix the Seafile startup issue (see above) and check MySQL logs:
     ```bash
     docker logs seafile-mysql
     ```

3. **Lambda Timeout**:
   * **Cause**: The Lambda function timed out while waiting for the SSM command to complete.
   * **Solution**: Increase the Lambda timeout to 15 minutes and ensure the EC2 instance is reachable via SSM.

4. **Permission Denied Errors**:
   * **Cause**: Incorrect IAM permissions for the EC2 instance, Lambda function, or GitHub Actions.
   * **Solution**: Verify the IAM roles have the required permissions (see the `TerraformExecutionRole` policy).

### Debugging

* **GitHub Actions Logs**: Check the workflow logs in the **Actions** tab for errors.
* **CloudWatch Logs**: Check the Lambda function logs in CloudWatch for errors.
* **SSM Command Output**: View the SSM command output in the AWS console to see the script’s execution details.
* **Container Logs**: Check the logs of all containers:
  ```bash
  docker logs seafile
  docker logs seafile-mysql
  docker logs seafile-redis
  ```

## Connecting to the EC2 Instance

You may need to connect to the EC2 instance for troubleshooting or to make further changes (e.g., updating configurations, checking logs, or running maintenance scripts). You can connect using AWS Systems Manager (SSM) Session Manager from the AWS Console, or via SSH from your local computer. Below are the steps for both methods.

### Method 1: Connect Using AWS Systems Manager (SSM) Session Manager

SSM Session Manager allows you to connect to the EC2 instance without needing SSH keys or opening inbound SSH ports. The EC2 instance is already configured with the necessary IAM role (`SeafileEC2Role`) to allow SSM access.

1. **Log in to the AWS Management Console**:
   * Navigate to the **EC2** service.

2. **Locate the EC2 Instance**:
   * In the EC2 dashboard, go to **Instances** in the left sidebar.
   * Find the instance with the tag `Name=seafile-instance`. Note its **Instance ID**.

3. **Start a Session**:
   * Select the instance and click **Connect** at the top.
   * In the **Connect to instance** page, select the **Session Manager** tab.
   * Click **Connect**.

4. **Access the Instance**:
   * A browser-based terminal will open, and you’ll be logged in as the `ssm-user`.
   * To switch to the `ec2-user` (which is used for the Seafile deployment), run:
     ```bash
     sudo su - ec2-user
     ```
   * You can now navigate to the Seafile directory (`/opt/seafile`) and perform troubleshooting or changes.

> **Note**: SSM Session Manager does not require SSH keys or inbound SSH ports (e.g., port 22), making it a secure option. Ensure your IAM user has permissions to use SSM (`AmazonSSMManagedInstanceCore` policy or equivalent).

### Method 2: Connect Using SSH from Your Local Computer

To connect via SSH, you’ll need the private key stored in AWS SSM Parameter Store, the public IP of the EC2 instance, and an SSH client (e.g., OpenSSH on Linux/macOS or PuTTY on Windows). The security group (`seafile-sg`) allows SSH access from a specific IP range, so ensure your IP matches the allowed CIDR (you may need to update the security group if your IP differs).

#### Step 1: Retrieve the Private Key from SSM Parameter Store

The private key for the EC2 instance is stored in SSM Parameter Store at the path `/seafile/ec2/keypair`.

1. **Retrieve the Key Using the AWS CLI**:
   * Run the following command to retrieve the private key:
     ```bash
     aws ssm get-parameter --name "/seafile/ec2/keypair" --with-decryption --region <region> --query Parameter.Value --output text > seafile-key-pair.pem
     ```
   * Replace `<region>` with your AWS region (e.g., `ap-southeast-1`).

2. **Set File Permissions**:
   * The private key file must have restricted permissions (readable only by the owner):
     ```bash
     chmod 400 seafile-key-pair.pem
     ```

#### Step 2: Get the Public IP of the EC2 Instance

* The public IP is output by Terraform as `seafile_elastic_ip`. If you deployed via GitHub Actions, check the workflow logs for this output. If you deployed manually, it’s displayed in the Terraform output.
* Alternatively, in the AWS Console:
  * Go to **EC2 > Instances**.
  * Find the instance with the tag `Name=seafile-instance`.
  * Note the **Public IPv4 address**.

#### Step 3: Connect via SSH

1. **Ensure Your IP is Allowed**:
   * The security group (`seafile-sg`) restricts SSH access (port 22) to a specific IP range. Check the inbound rules for the security group in the AWS Console under **EC2 > Security Groups**.
   * If your IP is not in the allowed range, update the security group to include your IP (e.g., `<your-ip>/32`).

2. **Connect Using SSH**:
   * Use the following command to connect to the EC2 instance:
     ```bash
     ssh -i seafile-key-pair.pem ec2-user@<public-ip>
     ```
   * Replace `<public-ip>` with the public IP of the EC2 instance (e.g., the `seafile_elastic_ip` output).
   * If prompted to verify the host, type `yes` and press Enter.

3. **Access the Instance**:
   * You’ll be logged in as the `ec2-user`.
   * Navigate to the Seafile directory to perform troubleshooting or changes:
     ```bash
     cd /opt/seafile
     ```

> **Note**: If you encounter a "Permission denied" error, double-check the file permissions of the `seafile-key-pair.pem` file (`chmod 400`) and ensure your IP is allowed in the security group.

## Maintenance

### Running Maintenance Scripts

Seafile maintenance scripts (e.g., `seaf-gc.sh`) must be run as the `seafile` user inside the container since `NON_ROOT=true` is set. Example:

```bash
docker exec seafile su seafile -c "/opt/seafile/seafile-pro-server-11.0.19/seaf-gc.sh"
```

### Updating Seafile

To update Seafile to a newer version:

1. Update the image tag in `docker-compose.yml` (e.g., `docker.seadrive.org/seafileltd/seafile-pro-mc:11.0-latest` to a newer version).
2. Run:
   ```bash
   docker-compose down
   docker-compose up -d
   ```

## Security Considerations

* **SSM Parameter Store**: Sensitive credentials are stored in SSM Parameter Store as `SecureString` to ensure encryption.
* **IAM Roles**: Use the principle of least privilege for all IAM roles.
* **Non-Root User**: Seafile runs as a non-root user (`NON_ROOT=true`), improving container security.
* **IAM Key Rotation**: Access keys are rotated monthly, and old keys are deleted after the new keys are applied.
* **Network Access**: The EC2 instance is in a VPC with a security group that allows HTTP (port 80), HTTPS (port 443), and restricted SSH access.
* **OIDC**: GitHub Actions uses OIDC to securely assume the `TerraformExecutionRole`, avoiding long-lived credentials.

## Contributing

Contributions are welcome! Please submit a pull request with your changes or open an issue to discuss improvements.
