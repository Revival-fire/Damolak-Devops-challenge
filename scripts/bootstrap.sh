#!/usr/bin/env bash
# bootstrap.sh — Run once before `terraform init`
# Creates: S3 state bucket, DynamoDB lock table, GitHub OIDC IAM role
set -euo pipefail


# Configuration — edit these before running


AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="${PROJECT_NAME:-devops-challenge}"
GITHUB_ORG="${GITHUB_ORG:-your-github-org}"
GITHUB_REPO="${GITHUB_REPO:-devops-challenge}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

BUCKET_NAME="${PROJECT_NAME}-tfstate-${ACCOUNT_ID}"
TABLE_NAME="${PROJECT_NAME}-tflock"
ROLE_NAME="${PROJECT_NAME}-github-actions-role"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Bootstrap: DevOps Challenge Infrastructure"
echo "Account  : ${ACCOUNT_ID}"
echo "Region   : ${AWS_REGION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Terraform state S3 bucket


if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "✅ S3 bucket already exists: ${BUCKET_NAME}"
else
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${AWS_REGION}" \
    $([ "${AWS_REGION}" != "us-east-1" ] && echo "--create-bucket-configuration LocationConstraint=${AWS_REGION}")

  # Enable versioning (critical for state recovery)
  aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled

  # Server-side encryption
  aws s3api put-bucket-encryption \
    --bucket "${BUCKET_NAME}" \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}
      }]
    }'

  # Block all public access
  aws s3api put-public-access-block \
    --bucket "${BUCKET_NAME}" \
    --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

  echo "✅ Created S3 bucket: ${BUCKET_NAME}"
fi


# 2. DynamoDB lock table


if aws dynamodb describe-table --table-name "${TABLE_NAME}" --region "${AWS_REGION}" 2>/dev/null; then
  echo "✅ DynamoDB table already exists: ${TABLE_NAME}"
else
  aws dynamodb create-table \
    --table-name "${TABLE_NAME}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${AWS_REGION}"
  echo "✅ Created DynamoDB table: ${TABLE_NAME}"
fi

# 3. GitHub OIDC Identity Provider


OIDC_URL="https://token.actions.githubusercontent.com"
OIDC_THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"

if aws iam list-open-id-connect-providers | grep -q "token.actions.githubusercontent.com"; then
  echo "✅ GitHub OIDC provider already exists"
else
  aws iam create-open-id-connect-provider \
    --url "${OIDC_URL}" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "${OIDC_THUMBPRINT}"
  echo "✅ Created GitHub OIDC provider"
fi

OIDC_PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"


# 4. IAM Role for GitHub Actions (keyless auth via OIDC)

TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_PROVIDER_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main"
        }
      }
    }
  ]
}
EOF
)

if aws iam get-role --role-name "${ROLE_NAME}" 2>/dev/null; then
  echo "✅ IAM role already exists: ${ROLE_NAME}"
else
  aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document "${TRUST_POLICY}" \
    --description "GitHub Actions OIDC role for ${GITHUB_ORG}/${GITHUB_REPO}"

  # Attach managed policies (least privilege — refine as needed)
  for POLICY in \
    "arn:aws:iam::aws:policy/AmazonECS_FullAccess" \
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess" \
    "arn:aws:iam::aws:policy/IAMFullAccess" \
    "arn:aws:iam::aws:policy/AmazonVPCFullAccess" \
    "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess" \
    "arn:aws:iam::aws:policy/CloudWatchFullAccess" \
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"; do
    aws iam attach-role-policy --role-name "${ROLE_NAME}" --policy-arn "${POLICY}"
  done

  # Inline policy for S3 state bucket
  aws iam put-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-name "TerraformStateAccess" \
    --policy-document "{
      \"Version\": \"2012-10-17\",
      \"Statement\": [
        {
          \"Effect\": \"Allow\",
          \"Action\": [\"s3:GetObject\",\"s3:PutObject\",\"s3:DeleteObject\",\"s3:ListBucket\"],
          \"Resource\": [
            \"arn:aws:s3:::${BUCKET_NAME}\",
            \"arn:aws:s3:::${BUCKET_NAME}/*\"
          ]
        }
      ]
    }"

  echo "✅ Created IAM role: ${ROLE_NAME}"
fi

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Bootstrap complete! Add these as GitHub Actions secrets:"
echo ""
echo "  AWS_ROLE_ARN      = ${ROLE_ARN}"
echo "  TF_STATE_BUCKET   = ${BUCKET_NAME}"
echo "  TF_LOCK_TABLE     = ${TABLE_NAME}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
