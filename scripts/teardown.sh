#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
REGION=${AWS_REGION:-us-east-1}
STACK_NAME="workflow-dev"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --region)
      REGION="$2"
      shift 2
      ;;
    --stack-name)
      STACK_NAME="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --region REGION        AWS region (default: us-east-1)"
      echo "  --stack-name NAME      CloudFormation stack name (default: workflow-dev)"
      echo "  -h, --help             Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Run with --help for usage information"
      exit 1
      ;;
  esac
done

export AWS_REGION=$REGION

echo -e "${RED}╔════════════════════════════════════════╗${NC}"
echo -e "${RED}║  AWS Workflow Teardown Script         ║${NC}"
echo -e "${RED}╚════════════════════════════════════════╝${NC}"
echo ""

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}✗ AWS CLI is not installed${NC}"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}✗ AWS credentials not configured${NC}"
    echo "  Please run: aws configure"
    exit 1
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

echo -e "${YELLOW}⚠️  WARNING: This will DELETE all AWS resources:${NC}"
echo ""
echo "  Region: ${REGION}"
echo "  Stack: ${STACK_NAME}"
echo ""
echo "  • DynamoDB Tables:"
echo "    - workflow_runs"
echo "    - workflow_steps"
echo "    - workflow_events"
echo "    - workflow_hooks"
echo "    - workflow_stream_chunks"
echo ""
echo "  • SQS Queues:"
echo "    - workflow-flows"
echo "    - workflow-steps"
echo "    - workflow-dlq"
echo ""
echo "  • S3 Bucket:"
echo "    - workflow-streams-${AWS_ACCOUNT}-${REGION}"
echo ""
echo "  • Lambda Function:"
echo "    - workflow-worker (and its layer)"
echo ""
echo "  • CloudFormation Stack:"
echo "    - ${STACK_NAME}"
echo ""
echo -e "${RED}🗑️  All workflow runs, steps, and data will be PERMANENTLY DELETED!${NC}"
echo ""

read -p "Are you absolutely sure you want to continue? (type 'yes' to confirm) " -r
echo
if [[ $REPLY != "yes" ]]; then
    echo -e "${BLUE}Teardown cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}🗑️  Destroying AWS resources...${NC}"

# Purge SQS queues first (to avoid Lambda invocations during deletion)
echo -e "${BLUE}1/5 Purging SQS queues...${NC}"
for queue in workflow-flows workflow-steps; do
    QUEUE_URL=$(aws sqs get-queue-url --queue-name $queue --region $REGION --output text 2>/dev/null || echo "")
    if [ -n "$QUEUE_URL" ]; then
        echo "  Purging: $queue"
        aws sqs purge-queue --queue-url "$QUEUE_URL" --region $REGION 2>/dev/null || true
    fi
done

# Empty S3 bucket (required before deletion)
echo -e "${BLUE}2/5 Emptying S3 bucket...${NC}"
BUCKET_NAME="workflow-streams-${AWS_ACCOUNT}-${REGION}"
if aws s3 ls "s3://${BUCKET_NAME}" --region $REGION 2>/dev/null; then
    echo "  Emptying: $BUCKET_NAME"
    aws s3 rm "s3://${BUCKET_NAME}" --recursive --region $REGION || true
fi

# Delete CloudFormation stack
echo -e "${BLUE}3/5 Deleting CloudFormation stack...${NC}"
if aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION &>/dev/null; then
    echo "  Deleting: $STACK_NAME"
    aws cloudformation delete-stack --stack-name $STACK_NAME --region $REGION
    echo "  Waiting for stack deletion (this may take a few minutes)..."
    aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME --region $REGION 2>/dev/null || true
else
    echo "  Stack not found (may have been deleted manually)"
fi

# Clean up any orphaned resources (in case CDK deletion failed)
echo -e "${BLUE}4/5 Cleaning up any orphaned resources...${NC}"

# Delete Lambda function if it still exists
if aws lambda get-function --function-name workflow-worker --region $REGION &>/dev/null; then
    echo "  Deleting orphaned Lambda: workflow-worker"
    aws lambda delete-function --function-name workflow-worker --region $REGION || true
fi

# Delete DynamoDB tables if they still exist
for table in workflow_runs workflow_steps workflow_events workflow_hooks workflow_stream_chunks; do
    if aws dynamodb describe-table --table-name $table --region $REGION &>/dev/null; then
        echo "  Deleting orphaned table: $table"
        aws dynamodb delete-table --table-name $table --region $REGION || true
    fi
done

# Delete SQS queues if they still exist
for queue in workflow-flows workflow-steps workflow-dlq; do
    QUEUE_URL=$(aws sqs get-queue-url --queue-name $queue --region $REGION --output text 2>/dev/null || echo "")
    if [ -n "$QUEUE_URL" ]; then
        echo "  Deleting orphaned queue: $queue"
        aws sqs delete-queue --queue-url "$QUEUE_URL" --region $REGION || true
    fi
done

# Clean up local artifacts
echo -e "${BLUE}5/5 Cleaning up local artifacts...${NC}"
rm -f .env.aws
rm -rf cdk.out

echo ""
echo -e "${BLUE}✅ Teardown complete!${NC}"
echo ""
echo "All AWS resources have been deleted."
echo ""

