#!/usr/bin/env bash
set -euo pipefail

TEMPLATE_DIR="aws.vpc.ecs"
TEMPLATES_PREFIX="templates"

echo "=== Vaadin AWS Deployment ==="
echo ""

read -rp "AWS Account ID: " AWS_ACCOUNT_ID
read -rp "AWS Region [eu-central-1]: " AWS_REGION
AWS_REGION="${AWS_REGION:-eu-central-1}"
read -rp "S3 Bucket for templates: " BUCKET
read -rp "App Name (lowercase, hyphens only): " APP_NAME
read -rsp "Database URL (JDBC connection string): " DATABASE_URL
echo ""

# Validate inputs
if [[ -z "$AWS_ACCOUNT_ID" || -z "$BUCKET" || -z "$APP_NAME" || -z "$DATABASE_URL" ]]; then
  echo "Error: All fields are required."
  exit 1
fi

if ! [[ "$APP_NAME" =~ ^[a-z0-9-]+$ ]]; then
  echo "Error: App name must be lowercase alphanumeric and hyphens only."
  exit 1
fi

echo ""
echo "--- Configuration ---"
echo "Account:  $AWS_ACCOUNT_ID"
echo "Region:   $AWS_REGION"
echo "Bucket:   $BUCKET"
echo "App Name: $APP_NAME"
echo "DB URL:   ********"
echo "---------------------"
echo ""
read -rp "Proceed? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

export AWS_DEFAULT_REGION="$AWS_REGION"

# Create S3 bucket if it doesn't exist
if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "Creating S3 bucket: $BUCKET"
  aws s3 mb "s3://$BUCKET" --region "$AWS_REGION"
fi

# Upload nested templates
echo "Uploading templates to s3://$BUCKET/$TEMPLATES_PREFIX/"
for template in vpc.yaml alb.yaml cloudfront.yaml ecs.yaml; do
  aws s3 cp "$TEMPLATE_DIR/$template" "s3://$BUCKET/$TEMPLATES_PREFIX/$template"
done

# Create the stack
echo "Creating CloudFormation stack: $APP_NAME"
aws cloudformation create-stack \
  --stack-name "$APP_NAME" \
  --template-body "file://$TEMPLATE_DIR/main.yaml" \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --parameters \
    ParameterKey=AppName,ParameterValue="$APP_NAME" \
    ParameterKey=DatabaseUrl,ParameterValue="$DATABASE_URL" \
    ParameterKey=TemplatesBucketName,ParameterValue="$BUCKET"

echo "Waiting for stack creation to complete..."
aws cloudformation wait stack-create-complete --stack-name "$APP_NAME"

echo ""
echo "=== Stack created successfully ==="
echo ""
aws cloudformation describe-stacks \
  --stack-name "$APP_NAME" \
  --query 'Stacks[0].Outputs' \
  --output table
