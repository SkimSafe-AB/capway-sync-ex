# AWS Configuration for CapwaySync

This document describes the AWS environment variables and configuration required for the CapwaySync application to store GeneralSyncReport data in DynamoDB.

## Required Environment Variables

### AWS Credentials

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `AWS_ACCESS_KEY_ID` | Yes (Prod) | AWS access key ID for authentication | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | Yes (Prod) | AWS secret access key for authentication | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `AWS_REGION` | Yes | AWS region where DynamoDB table is located | `us-east-1`, `eu-west-1` |
| `AWS_SESSION_TOKEN` | No | Session token for temporary credentials (STS) | Used with IAM roles/assumed roles |

### DynamoDB Configuration

| Variable | Required | Description | Default | Example |
|----------|----------|-------------|---------|---------|
| `SYNC_REPORTS_TABLE` | No | DynamoDB table name for storing sync reports | `capway-sync-reports` | `capway-sync-reports-prod` |
| `DYNAMODB_HOST` | No | Override DynamoDB endpoint (for LocalStack) | AWS default | `localhost` |

## Environment-Specific Configuration

### Production Environment

```bash
# Required AWS credentials
export AWS_ACCESS_KEY_ID="your-production-access-key"
export AWS_SECRET_ACCESS_KEY="your-production-secret-key"
export AWS_REGION="us-east-1"

# Production table name
export SYNC_REPORTS_TABLE="capway-sync-reports-prod"
```

### Development Environment

```bash
# AWS credentials (can be dev account or LocalStack)
export AWS_ACCESS_KEY_ID="your-dev-access-key"
export AWS_SECRET_ACCESS_KEY="your-dev-secret-key"
export AWS_REGION="us-east-1"

# Development table name
export SYNC_REPORTS_TABLE="capway-sync-reports-dev"

# Optional: Use LocalStack for local development
export USE_LOCALSTACK="true"
export LOCALSTACK_HOST="localhost"
export LOCALSTACK_PORT="4566"
```

### Test Environment

```bash
# Test credentials (will use fake credentials if not provided)
export AWS_ACCESS_KEY_ID="test-key"
export AWS_SECRET_ACCESS_KEY="test-secret"
export AWS_REGION="us-east-1"

# Test table name
export SYNC_REPORTS_TABLE="capway-sync-reports-test"

# LocalStack for testing
export DYNAMODB_TEST_HOST="localhost"
export DYNAMODB_TEST_PORT="4566"
```

## DynamoDB Table Setup

### Table Schema

The DynamoDB table should have the following configuration:

```yaml
Table Name: capway-sync-reports (or value from SYNC_REPORTS_TABLE)
Partition Key: report_id (String)
Sort Key: created_at (String, ISO8601 format)
Billing Mode: On-demand (recommended) or Provisioned
```

### Table Creation (AWS CLI)

```bash
aws dynamodb create-table \
  --table-name capway-sync-reports \
  --attribute-definitions \
    AttributeName=report_id,AttributeType=S \
    AttributeName=created_at,AttributeType=S \
  --key-schema \
    AttributeName=report_id,KeyType=HASH \
    AttributeName=created_at,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### Table Creation (Terraform)

```hcl
resource "aws_dynamodb_table" "capway_sync_reports" {
  name           = "capway-sync-reports"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "report_id"
  range_key      = "created_at"

  attribute {
    name = "report_id"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  tags = {
    Name        = "CapwaySync Reports"
    Environment = "production"
    Application = "capway-sync"
  }
}
```

## LocalStack Development Setup

For local development without AWS, you can use LocalStack:

### Docker Compose

```yaml
# docker-compose.yml
services:
  localstack:
    image: localstack/localstack:latest
    ports:
      - "4566:4566"
    environment:
      - SERVICES=dynamodb
      - DEBUG=1
      - DATA_DIR=/tmp/localstack/data
    volumes:
      - localstack-data:/tmp/localstack

volumes:
  localstack-data:
```

### Create Table in LocalStack

```bash
# Start LocalStack
docker-compose up -d localstack

# Create table
aws dynamodb create-table \
  --table-name capway-sync-reports-dev \
  --attribute-definitions \
    AttributeName=report_id,AttributeType=S \
    AttributeName=created_at,AttributeType=S \
  --key-schema \
    AttributeName=report_id,KeyType=HASH \
    AttributeName=created_at,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST \
  --endpoint-url http://localhost:4566 \
  --region us-east-1
```

## IAM Permissions

### Minimum Required Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CapwaySyncDynamoDBAccess",
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:DeleteItem",
        "dynamodb:Scan",
        "dynamodb:Query",
        "dynamodb:DescribeTable"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/capway-sync-reports*"
    }
  ]
}
```

### Recommended Production Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CapwaySyncDynamoDBAccess",
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:DeleteItem",
        "dynamodb:Scan",
        "dynamodb:Query",
        "dynamodb:DescribeTable",
        "dynamodb:ListTables"
      ],
      "Resource": [
        "arn:aws:dynamodb:us-east-1:123456789012:table/capway-sync-reports-prod",
        "arn:aws:dynamodb:us-east-1:123456789012:table/capway-sync-reports-prod/index/*"
      ],
      "Condition": {
        "StringEquals": {
          "dynamodb:LeadingKeys": ["${aws:userid}"]
        }
      }
    }
  ]
}
```

## Authentication Methods

### 1. IAM User Credentials

```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="us-east-1"
```

### 2. IAM Role (EC2/ECS/Lambda)

When running on AWS infrastructure, use IAM roles instead of access keys:

```bash
# Only region needed, credentials from instance metadata
export AWS_REGION="us-east-1"
# AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY not needed
```

### 3. Temporary Credentials (STS)

```bash
export AWS_ACCESS_KEY_ID="temp-access-key"
export AWS_SECRET_ACCESS_KEY="temp-secret-key"
export AWS_SESSION_TOKEN="session-token"
export AWS_REGION="us-east-1"
```

## Configuration Validation

To verify your configuration is correct, you can test it with:

```bash
# Test AWS credentials
aws sts get-caller-identity --region $AWS_REGION

# Test DynamoDB access
aws dynamodb describe-table --table-name $SYNC_REPORTS_TABLE --region $AWS_REGION

# Test with the application (in iex console)
iex -S mix
> CapwaySync.Dynamodb.GeneralSyncReportRepository.test_get_table_name()
```

## Troubleshooting

### Common Issues

1. **Invalid Credentials**: Check `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
2. **Access Denied**: Verify IAM permissions for the table
3. **Table Not Found**: Ensure table exists and `SYNC_REPORTS_TABLE` is correct
4. **Region Mismatch**: Verify `AWS_REGION` matches table location
5. **LocalStack Connection**: Check `USE_LOCALSTACK` and LocalStack is running

### Debug Mode

Enable debug logging for AWS requests:

```bash
export AWS_DEBUG=true
```

Or in config:

```elixir
config :ex_aws,
  debug_requests: true,
  recv_timeout: 60_000
```

## Security Best Practices

1. **Never commit AWS credentials** to version control
2. **Use IAM roles** when running on AWS infrastructure
3. **Rotate access keys** regularly
4. **Use least privilege** IAM policies
5. **Enable CloudTrail** for audit logging
6. **Use VPC endpoints** for private DynamoDB access
7. **Enable encryption at rest** for the DynamoDB table