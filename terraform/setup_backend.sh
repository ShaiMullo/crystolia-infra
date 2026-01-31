#!/bin/bash

# Configuration
BUCKET_NAME="crystolia-terraform-state"
TABLE_NAME="crystolia-terraform-locks"
REGION="us-east-1"

echo "🚀 Bootstrapping Terraform Backend..."

# 1. Create S3 Bucket
if aws s3 ls "s3://$BUCKET_NAME" 2>&1 | grep -q 'NoSuchBucket'; then
  echo "📦 Creating S3 Bucket: $BUCKET_NAME..."
  aws s3 mb "s3://$BUCKET_NAME" --region "$REGION"
  
  # Enable versioning
  aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" --versioning-configuration Status=Enabled
else
  echo "✅ Bucket $BUCKET_NAME already exists."
fi

# 2. Create DynamoDB Table for locking
if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" > /dev/null 2>&1; then
  echo "✅ DynamoDB Table $TABLE_NAME already exists."
else
  echo "🔒 Creating DynamoDB Table: $TABLE_NAME..."
  aws dynamodb create-table \
    --table-name "$TABLE_NAME" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --region "$REGION"
fi

echo "🎉 Backend configured! You can now run 'terraform init'."
