#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
REGION=${AWS_REGION:-us-east-1}
STACK_NAME="WorkflowStack"
SKIP_CONFIRM=false

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
    -y|--yes)
      SKIP_CONFIRM=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --region REGION        AWS region (default: us-east-1)"
      echo "  --stack-name NAME      CloudFormation stack name (default: WorkflowStack)"
      echo "  -y, --yes              Skip confirmation prompts"
      echo "  -h, --help             Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0                                    # Use defaults"
      echo "  $0 --region us-west-2                 # Deploy to us-west-2"
      echo "  $0 --region eu-west-1 -y              # Deploy to EU with no prompts"
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

echo ""
echo -e "${BLUE}                        ■                        ${NC}"
echo -e "${BLUE}                       ■ ■                       ${NC}"
echo -e "${BLUE}                      ■ ■ ■                      ${NC}"
echo ""
echo -e "${GREEN}     █████╗ ██╗    ██╗███████╗              ${NC}"
echo -e "${GREEN}    ██╔══██╗██║    ██║██╔════╝              ${NC}"
echo -e "${GREEN}    ███████║██║ █╗ ██║███████╗              ${NC}"
echo -e "${GREEN}    ██╔══██║██║███╗██║╚════██║              ${NC}"
echo -e "${GREEN}    ██║  ██║╚███╔███╔╝███████║              ${NC}"
echo -e "${GREEN}    ╚═╝  ╚═╝ ╚══╝╚══╝ ╚══════╝              ${NC}"
echo ""
echo -e "${YELLOW}    ██╗    ██╗ ██████╗ ██████╗ ██╗  ██╗███████╗██╗      ██████╗ ██╗    ██╗${NC}"
echo -e "${YELLOW}    ██║    ██║██╔═══██╗██╔══██╗██║ ██╔╝██╔════╝██║     ██╔═══██╗██║    ██║${NC}"
echo -e "${YELLOW}    ██║ █╗ ██║██║   ██║██████╔╝█████╔╝ █████╗  ██║     ██║   ██║██║ █╗ ██║${NC}"
echo -e "${YELLOW}    ██║███╗██║██║   ██║██╔══██╗██╔═██╗ ██╔══╝  ██║     ██║   ██║██║███╗██║${NC}"
echo -e "${YELLOW}    ╚███╔███╔╝╚██████╔╝██║  ██║██║  ██╗██║     ███████╗╚██████╔╝╚███╔███╔╝${NC}"
echo -e "${YELLOW}     ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚══════╝ ╚═════╝  ╚══╝╚══╝ ${NC}"
echo ""
echo -e "${BLUE}    ═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                        Bootstrap Script v1.0                        ${NC}"
echo -e "${BLUE}    ═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Check prerequisites
echo -e "${BLUE}🔍 Checking prerequisites...${NC}"

# Check Node.js
if ! command -v node &> /dev/null; then
    echo -e "${RED}✗ Node.js is not installed${NC}"
    echo "  Please install Node.js 18 or higher"
    exit 1
fi
NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    echo -e "${RED}✗ Node.js version must be 18 or higher (current: $(node -v))${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Node.js $(node -v)${NC}"

# Check pnpm
if ! command -v pnpm &> /dev/null; then
    echo -e "${YELLOW}! pnpm not found, installing...${NC}"
    npm install -g pnpm
fi
echo -e "${GREEN}✓ pnpm $(pnpm -v)${NC}"

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}✗ AWS CLI is not installed${NC}"
    echo "  Please install AWS CLI: https://aws.amazon.com/cli/"
    exit 1
fi
echo -e "${GREEN}✓ AWS CLI $(aws --version | cut -d' ' -f1)${NC}"

echo ""
# Note: AWS CDK will be available via pnpm (installed as dependency)

# Check AWS credentials
echo -e "${BLUE}🔐 Checking AWS credentials...${NC}"
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}✗ AWS credentials not configured${NC}"
    echo "  Please run: aws configure"
    exit 1
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✓ AWS Account: $AWS_ACCOUNT${NC}"
echo -e "${GREEN}✓ AWS Region: $REGION${NC}"
echo -e "${GREEN}✓ Stack Name: $STACK_NAME${NC}"

echo ""

# Install dependencies
echo -e "${BLUE}📦 Installing dependencies...${NC}"
pnpm install

echo ""

# Build TypeScript
echo -e "${BLUE}🔨 Building TypeScript...${NC}"
pnpm build

echo ""

# Deploy infrastructure
echo -e "${BLUE}🏗️  Deploying AWS infrastructure...${NC}"
echo -e "${YELLOW}This will create:${NC}"
echo "  • 5 DynamoDB tables (runs, steps, events, hooks, streams)"
echo "  • 3 SQS queues (workflow, step, dead-letter)"
echo "  • 1 S3 bucket for stream storage"
echo "  • 1 Lambda function with layer"
echo ""

if [ "$SKIP_CONFIRM" = false ]; then
    read -p "Continue with deployment? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Deployment cancelled${NC}"
        exit 0
    fi
else
    echo -e "${GREEN}Auto-confirmed (--yes flag)${NC}"
    echo ""
fi

# Build Lambda bundle (Next.js workflows + Lambda handler)
echo -e "${BLUE}📦 Building Lambda bundle...${NC}"
./scripts/build.sh

echo ""

# Bootstrap CDK (if needed)
echo -e "${BLUE}🚀 Bootstrapping AWS CDK...${NC}"
if command -v cdk &> /dev/null; then
    cdk bootstrap aws://$AWS_ACCOUNT/$REGION
else
    npx --yes aws-cdk@latest bootstrap aws://$AWS_ACCOUNT/$REGION
fi

echo ""

# Deploy with CDK
echo "🚀 Deploying CloudFormation stack..."
if command -v cdk &> /dev/null; then
    npx cdk deploy --require-approval never
else
    npx --yes aws-cdk@latest deploy --require-approval never
fi

echo ""

# Get outputs
echo -e "${BLUE}📋 Extracting deployment outputs...${NC}"
AWS_REGION=$REGION ./scripts/outputs.sh "workflow-dev" > .env.aws

# Display environment variables
echo ""
echo -e "${GREEN}✅ Bootstrap complete!${NC}"
echo ""
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Environment Variables                 ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""
cat .env.aws
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT: Add these environment variables to your Next.js app:${NC}"
echo ""
echo -e "  1. Copy the variables from ${BLUE}.env.aws${NC} to your Next.js ${BLUE}.env.local${NC} file"
echo -e "  2. Add your AWS credentials (if running locally):"
echo -e "     ${BLUE}AWS_ACCESS_KEY_ID${NC}=your-access-key"
echo -e "     ${BLUE}AWS_SECRET_ACCESS_KEY${NC}=your-secret-key"
echo -e "     ${BLUE}AWS_REGION${NC}=${REGION}"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo -e "  1. Copy ${BLUE}.env.aws${NC} variables to your Next.js ${BLUE}.env.local${NC}"
echo -e "  2. Add AWS credentials to ${BLUE}.env.local${NC} (for local development)"
echo -e "  3. Write your workflows in your Next.js app"
echo -e "  4. When you update workflows: ${BLUE}npm run deploy${NC}"
echo ""
echo -e "${GREEN}✅ Your workflows are now deployed and ready to use!${NC}"
echo ""

