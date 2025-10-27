#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Determine if we're running from the package or from a user's project
if [ -n "$AWS_WORKFLOW_PACKAGE_ROOT" ]; then
  # Running from user's project via npx
  PACKAGE_ROOT="$AWS_WORKFLOW_PACKAGE_ROOT"
  PROJECT_ROOT="$(pwd)"
else
  # Running from within the package (development mode)
  PACKAGE_ROOT="$(pwd)"
  PROJECT_ROOT="$PACKAGE_ROOT/examples/nextjs-example"
fi

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

# Get AWS credentials from environment if set
if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
  export AWS_ACCESS_KEY_ID
  export AWS_SECRET_ACCESS_KEY
fi

# Ensure AWS_REGION is exported
export AWS_REGION=$REGION

# Check AWS credentials
echo -e "${BLUE}🔐 Checking AWS credentials...${NC}"
if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
  echo -e "${GREEN}✓ Using AWS credentials from environment variables${NC}"
fi

if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}✗ AWS credentials not configured${NC}"
    echo "  Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables,"
    echo "  or run 'aws configure' to set up credentials."
    exit 1
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✓ AWS Account: $AWS_ACCOUNT${NC}"
echo -e "${GREEN}✓ AWS Region: $REGION${NC}"
echo -e "${GREEN}✓ Stack Name: $STACK_NAME${NC}"

echo ""

# Compile aws-workflow package TypeScript if needed
echo -e "${BLUE}📦 Compiling aws-workflow package...${NC}"
cd "$PACKAGE_ROOT"
if [ ! -d "dist" ] || [ ! -f "dist/bin/aws-workflow.js" ]; then
  echo "   Compiling TypeScript..."
  pnpm tsc --build
else
  echo "   ✓ Already compiled"
fi

echo ""

# Create placeholder Lambda bundle for initial deployment
echo -e "${BLUE}📦 Creating placeholder Lambda bundle...${NC}"
rm -rf cdk.out/lambda-bundle
mkdir -p cdk.out/lambda-bundle/.well-known/workflow/v1/flow
mkdir -p cdk.out/lambda-bundle/.well-known/workflow/v1/step

# Create placeholder handler
cat > cdk.out/lambda-bundle/index.js << 'EOF'
exports.handler = async (event) => {
  console.log('Placeholder handler - deploy your workflows with: npx aws-workflow deploy');
  return {
    statusCode: 200,
    body: JSON.stringify({ message: 'Placeholder - run npx aws-workflow deploy' })
  };
};
EOF

# Create placeholder route handlers
cat > cdk.out/lambda-bundle/.well-known/workflow/v1/flow/route.js << 'EOF'
export const POST = async (request) => {
  return new Response(JSON.stringify({ error: 'Placeholder - run npx aws-workflow deploy' }), {
    status: 503,
    headers: { 'Content-Type': 'application/json' }
  });
};
EOF

cat > cdk.out/lambda-bundle/.well-known/workflow/v1/step/route.js << 'EOF'
export const POST = async (request) => {
  return new Response(JSON.stringify({ error: 'Placeholder - run npx aws-workflow deploy' }), {
    status: 503,
    headers: { 'Content-Type': 'application/json' }
  });
};
EOF

# Create minimal package.json
cat > cdk.out/lambda-bundle/package.json << 'EOF'
{
  "name": "workflow-lambda-worker",
  "version": "1.0.0",
  "type": "module",
  "main": "index.js"
}
EOF

echo "   ✓ Placeholder bundle created"
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

# Bootstrap CDK (if needed)
echo -e "${BLUE}🚀 Bootstrapping AWS CDK...${NC}"
cd "$PACKAGE_ROOT"
if command -v cdk &> /dev/null; then
    cdk bootstrap aws://$AWS_ACCOUNT/$REGION
else
    npx --yes aws-cdk@latest bootstrap aws://$AWS_ACCOUNT/$REGION
fi

echo ""

# Deploy with CDK (infrastructure only)
echo "🚀 Deploying CloudFormation stack (infrastructure only)..."
cd "$PACKAGE_ROOT"
if command -v cdk &> /dev/null; then
    npx cdk deploy --require-approval never
else
    npx --yes aws-cdk@latest deploy --require-approval never
fi

echo ""

# Get outputs
echo -e "${BLUE}📋 Extracting deployment outputs...${NC}"
cd "$PROJECT_ROOT"
AWS_REGION=$REGION bash "$PACKAGE_ROOT/scripts/outputs.sh" "$STACK_NAME" > .env.aws

# Display environment variables
echo ""
echo -e "${GREEN}✅ Infrastructure bootstrap complete!${NC}"
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
echo -e "${GREEN}✨ Next steps:${NC}"
echo ""
echo -e "  1. Deploy your workflow code to Lambda:"
echo -e "     ${BLUE}npx aws-workflow deploy${NC}"
echo ""
echo -e "  2. Test your workflow locally:"
echo -e "     ${BLUE}pnpm dev${NC}"
echo ""
echo -e "  3. View Lambda logs:"
echo -e "     ${BLUE}npx aws-workflow logs${NC}"
echo ""

