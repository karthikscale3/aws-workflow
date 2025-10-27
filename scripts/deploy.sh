#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
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

# For backwards compatibility
AWS_WORKFLOW_DIR="$PACKAGE_ROOT"
NEXTJS_DIR="$PROJECT_ROOT"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Deploy Workflows to AWS Lambda        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
echo -e "${BLUE}🔍 Checking prerequisites...${NC}"

# Check Node.js
if ! command -v node &> /dev/null; then
    echo -e "${RED}✗ Node.js is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Node.js $(node -v)${NC}"

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}✗ AWS CLI is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ AWS CLI${NC}"

# Get AWS region from environment or AWS CLI config
if [ -z "$AWS_REGION" ]; then
  AWS_REGION=$(aws configure get region 2>/dev/null)
fi

# Prompt for region if not set
if [ -z "$AWS_REGION" ]; then
  echo -e "${YELLOW}⚠️  AWS_REGION not set${NC}"
  echo ""
  read -p "Enter AWS region (default: us-east-1): " user_region
  AWS_REGION=${user_region:-us-east-1}
  echo ""
fi
export AWS_REGION

# Check if AWS credentials are available
CREDS_AVAILABLE=false

# Check environment variables
if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
  echo -e "${GREEN}✓ Using AWS credentials from environment variables${NC}"
  export AWS_ACCESS_KEY_ID
  export AWS_SECRET_ACCESS_KEY
  CREDS_AVAILABLE=true
fi

# Check if AWS CLI is configured
if [ "$CREDS_AVAILABLE" = false ]; then
  if aws sts get-caller-identity &> /dev/null; then
    echo -e "${GREEN}✓ Using AWS credentials from AWS CLI config${NC}"
    CREDS_AVAILABLE=true
  fi
fi

# Prompt for credentials if not available
if [ "$CREDS_AVAILABLE" = false ]; then
  echo -e "${YELLOW}⚠️  AWS credentials not configured${NC}"
  echo ""
  echo "You can either:"
  echo "  1. Enter credentials now"
  echo "  2. Configure AWS CLI (run 'aws configure' in another terminal)"
  echo ""
  read -p "Would you like to enter credentials now? (y/N): " -n 1 -r
  echo ""
  
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    read -p "Enter AWS_ACCESS_KEY_ID: " input_access_key
    read -sp "Enter AWS_SECRET_ACCESS_KEY: " input_secret_key
    echo ""
    echo ""
    
    if [ -n "$input_access_key" ] && [ -n "$input_secret_key" ]; then
      export AWS_ACCESS_KEY_ID="$input_access_key"
      export AWS_SECRET_ACCESS_KEY="$input_secret_key"
      echo -e "${GREEN}✓ Credentials set${NC}"
      CREDS_AVAILABLE=true
    else
      echo -e "${RED}✗ Invalid credentials${NC}"
      exit 1
    fi
  else
    echo -e "${RED}✗ Cannot proceed without AWS credentials${NC}"
    echo "  Please set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables,"
    echo "  or run 'aws configure' to set up credentials."
    exit 1
  fi
fi

# Verify credentials work
echo ""
echo -e "${BLUE}🔐 Verifying AWS credentials...${NC}"
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}✗ AWS credentials are invalid or insufficient permissions${NC}"
    exit 1
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✓ AWS Account: $AWS_ACCOUNT${NC}"
echo -e "${GREEN}✓ AWS Region: $AWS_REGION${NC}"
echo ""

# Check if .env.aws exists and warn user about environment variables
if [ -f "$PROJECT_ROOT/.env.aws" ]; then
  echo -e "${BLUE}📋 Checking workflow environment variables...${NC}"
  
  # Check if key environment variables are set
  MISSING_VARS=()
  
  # Read required variables from .env.aws
  while IFS='=' read -r key value; do
    # Skip comments and empty lines
    [[ "$key" =~ ^#.*$ ]] && continue
    [[ -z "$key" ]] && continue
    
    # Check if this variable is set in current environment
    if [ -z "${!key}" ]; then
      MISSING_VARS+=("$key")
    fi
  done < "$PROJECT_ROOT/.env.aws"
  
  if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Warning: Workflow environment variables not set!${NC}"
    echo ""
    echo "The following variables from .env.aws are not in your environment:"
    for var in "${MISSING_VARS[@]}"; do
      echo "  - $var"
    done
    echo ""
    echo -e "${YELLOW}These variables are needed for your Next.js app to connect to AWS resources.${NC}"
    echo ""
    echo "To fix this:"
    echo "  1. Copy variables from .env.aws to your Next.js .env.local file:"
    echo -e "     ${BLUE}cat .env.aws >> .env.local${NC}"
    echo ""
    echo "  2. Or source them for this session:"
    echo -e "     ${BLUE}source .env.aws${NC}"
    echo ""
    read -p "Continue deployment anyway? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo -e "${YELLOW}Deployment cancelled. Please set up environment variables first.${NC}"
      exit 0
    fi
    echo ""
  else
    echo -e "${GREEN}✓ Workflow environment variables are set${NC}"
    echo ""
  fi
else
  echo -e "${YELLOW}⚠️  .env.aws file not found${NC}"
  echo ""
  echo "It looks like you haven't run 'npx aws-workflow bootstrap' yet,"
  echo "or you're running this from a different directory."
  echo ""
  read -p "Continue deployment anyway? (y/N): " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Deployment cancelled.${NC}"
    exit 0
  fi
  echo ""
fi

# Step 1: Compile TypeScript in aws-workflow package
echo -e "${BLUE}📦 Step 1/3: Compiling aws-workflow package...${NC}"
cd "$AWS_WORKFLOW_DIR"

# Check if we need to install dependencies
if [ ! -d "node_modules" ]; then
  echo "   Installing aws-workflow dependencies..."
  if command -v pnpm &> /dev/null; then
    pnpm install --prod
  else
    npm install --production
  fi
fi

# Compile TypeScript
if command -v pnpm &> /dev/null; then
  pnpm tsc --build
else
  npx tsc --build
fi

# Compile Lambda handler as ESM
if command -v pnpm &> /dev/null; then
  pnpm tsc --project lambda/tsconfig.json
else
  npx tsc --project lambda/tsconfig.json
fi

echo "   ✓ TypeScript compiled"
echo ""

# Step 2: Build Next.js app to generate workflow bundles
echo -e "${BLUE}📦 Step 2/3: Building Next.js workflows...${NC}"
cd "$NEXTJS_DIR"

# Check if Next.js dependencies are installed
if [ ! -d "node_modules" ]; then
  echo "   Installing Next.js dependencies..."
  if [ -f "pnpm-lock.yaml" ]; then
    pnpm install
  elif [ -f "package-lock.json" ]; then
    npm install
  elif [ -f "yarn.lock" ]; then
    yarn install
  else
    npm install
  fi
fi

# Use npm for Next.js build to avoid .pnpm path issues
if [ ! -f "package-lock.json" ]; then
  echo "   Converting to npm for flat node_modules structure..."
  rm -rf node_modules pnpm-lock.yaml yarn.lock
  npm install --legacy-peer-deps
fi

# Build Next.js
export WORKFLOW_TARGET_WORLD=aws-workflow
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY

npm run build

echo "   ✓ Workflow bundles generated"
echo ""

# Step 3: Prepare Lambda bundle
echo -e "${BLUE}📦 Step 3/3: Preparing Lambda bundle...${NC}"
cd "$AWS_WORKFLOW_DIR"

rm -rf cdk.out/lambda-bundle
mkdir -p cdk.out/lambda-bundle

# Copy workflow route files from user's Next.js app
echo "   Copying workflow routes..."
mkdir -p cdk.out/lambda-bundle/.well-known/workflow/v1/flow
mkdir -p cdk.out/lambda-bundle/.well-known/workflow/v1/step
cp "$NEXTJS_DIR/app/.well-known/workflow/v1/flow/route.js" cdk.out/lambda-bundle/.well-known/workflow/v1/flow/
cp "$NEXTJS_DIR/app/.well-known/workflow/v1/step/route.js" cdk.out/lambda-bundle/.well-known/workflow/v1/step/

# Copy Lambda handler (compiled as ESM)
echo "   Copying Lambda handler..."
cp dist/lambda/worker/index.js cdk.out/lambda-bundle/index.js

# Create package.json (ESM for both handler and route files)
echo "   Creating package.json..."
cat > cdk.out/lambda-bundle/package.json << 'EOF'
{
  "name": "workflow-lambda-worker",
  "version": "1.0.0",
  "type": "module",
  "main": "index.js",
  "dependencies": {
    "@vercel/queue": "0.0.0-alpha.23",
    "@workflow/errors": "4.0.1-beta.1",
    "@workflow/world": "4.0.1-beta.1",
    "workflow": "4.0.1-beta.1",
    "ulid": "^3.0.1",
    "zod": "^4.1.11"
  }
}
EOF

# Install dependencies with npm (flat structure)
echo "   Installing Lambda dependencies..."
cd cdk.out/lambda-bundle
npm install --production --no-package-lock --legacy-peer-deps --quiet

# Clean up unnecessary packages
echo "   Optimizing bundle size..."
rm -rf node_modules/typescript node_modules/@types
rm -rf node_modules/esbuild node_modules/@esbuild
rm -rf node_modules/@swc node_modules/@img
rm -rf node_modules/.bin
rm -rf node_modules/@aws-sdk node_modules/@smithy node_modules/@aws-crypto
rm -rf node_modules/next node_modules/@next
rm -rf node_modules/react node_modules/react-dom
rm -rf node_modules/@babel node_modules/webpack
rm -rf node_modules/postcss node_modules/tailwindcss
rm -rf node_modules/date-fns node_modules/lodash
rm -rf node_modules/.cache

# Bundle aws-workflow package AFTER npm install
echo "   Bundling aws-workflow package..."
mkdir -p node_modules/aws-workflow
cd ../../

# Bundle with esbuild
npx esbuild dist/world/index.js \
  --bundle \
  --platform=node \
  --target=node20 \
  --format=cjs \
  --outfile=cdk.out/lambda-bundle/node_modules/aws-workflow/index.js \
  --external:@aws-sdk/* \
  --external:ulid \
  --external:ms \
  --external:zod

# Create package.json for aws-workflow
cat > cdk.out/lambda-bundle/node_modules/aws-workflow/package.json << 'EOF'
{
  "name": "aws-workflow",
  "type": "commonjs",
  "main": "index.js"
}
EOF

BUNDLE_SIZE=$(du -sh cdk.out/lambda-bundle | cut -f1)
echo "   ✓ Lambda bundle ready ($BUNDLE_SIZE)"
echo ""

# Deploy with CDK
echo -e "${BLUE}🚀 Deploying to AWS Lambda...${NC}"
npx cdk deploy \
    --require-approval never \
    --outputs-file cdk.out/outputs.json

echo ""
echo -e "${BLUE}⏳ Waiting for Lambda update to complete...${NC}"
aws lambda wait function-updated \
    --region $AWS_REGION \
    --function-name workflow-worker

echo ""
echo -e "${GREEN}✅ Deployment complete!${NC}"
echo ""
echo -e "${GREEN}Your workflows are now running on AWS Lambda.${NC}"
echo -e "${YELLOW}💡 Trigger a workflow from your Next.js app to test it.${NC}"
echo ""

