#!/usr/bin/env bash
set -euo pipefail

echo "=== Vaadin AWS Teardown ==="
echo ""

read -rp "Stack Name (App Name): " APP_NAME
read -rp "S3 Bucket to clean up: " BUCKET
read -rp "AWS Region [eu-central-1]: " AWS_REGION
AWS_REGION="${AWS_REGION:-eu-central-1}"

if [[ -z "$APP_NAME" || -z "$BUCKET" ]]; then
  echo "Error: All fields are required."
  exit 1
fi

export AWS_DEFAULT_REGION="$AWS_REGION"

echo ""
echo "This will PERMANENTLY DELETE:"
echo "  - CloudFormation stack: $APP_NAME (and all its resources)"
echo "  - S3 bucket: $BUCKET (and all its contents)"
echo "  - Secrets Manager secret: ${APP_NAME}/database-url"
echo ""
read -rp "Are you sure? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

# Force-delete the Secrets Manager secret (skip 30-day recovery window)
echo "Force-deleting Secrets Manager secret..."
aws secretsmanager delete-secret \
  --secret-id "${APP_NAME}/database-url" \
  --force-delete-without-recovery 2>/dev/null || echo "  Secret not found or already deleted."

# Delete the CloudFormation stack
echo "Deleting CloudFormation stack: $APP_NAME"
aws cloudformation delete-stack --stack-name "$APP_NAME"

echo "Waiting for stack deletion to complete (this may take several minutes)..."
aws cloudformation wait stack-delete-complete --stack-name "$APP_NAME"
echo "Stack deleted."

# Clean up the S3 bucket
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "Emptying S3 bucket: $BUCKET"
  aws s3 rm "s3://$BUCKET" --recursive
  echo "Deleting S3 bucket: $BUCKET"
  aws s3 rb "s3://$BUCKET"
  echo "Bucket deleted."
else
  echo "S3 bucket '$BUCKET' not found, skipping."
fi

echo ""
echo "=== Teardown complete ==="
