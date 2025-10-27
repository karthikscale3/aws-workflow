# aws-workflow

![Experimental](https://img.shields.io/badge/status-experimental-orange?style=flat-square) ![Beta](https://img.shields.io/badge/status-beta-yellow?style=flat-square)

> ⚠️ **EXPERIMENTAL & BETA**: This package is in active development and should be used with caution in production.

AWS World implementation for [Workflow DevKit](https://useworkflow.dev/) - Run durable, resumable workflows on AWS Lambda with DynamoDB, SQS, and S3.

## What is Workflow DevKit?

[Workflow DevKit](https://useworkflow.dev/) brings durability, reliability, and observability to async JavaScript. Build workflows and AI Agents that can suspend, resume, and maintain state with ease - all with simple TypeScript functions.

`aws-workflow` is a **World** implementation that runs your workflows on AWS infrastructure, providing:
- ✅ Serverless execution on AWS Lambda
- ✅ State persistence with DynamoDB
- ✅ Message queuing with SQS
- ✅ Large payload storage with S3
- ✅ Automatic retries and error handling
- ✅ No vendor lock-in - same code runs locally or on any cloud

## Quick Start

### Prerequisites

- Node.js 18+
- AWS CLI configured with credentials
- A Next.js 14+ application

### 1. Install

```bash
npm install aws-workflow workflow
```

### 2. Bootstrap AWS Resources

This creates the required AWS infrastructure (DynamoDB tables, SQS queues, S3 bucket, Lambda function):

```bash
npx aws-workflow bootstrap -y
```

**What this does:**
- Creates 5 DynamoDB tables (workflow runs, steps, events, hooks, stream chunks)
- Creates 2 SQS queues (workflow queue, step queue)
- Creates 1 S3 bucket for large payload storage
- Deploys Lambda worker function
- Outputs environment variables to `.env.aws`

**Cost estimate:** Free tier eligible. Typical cost: $5-20/month for moderate usage.

### 3. Configure Your Next.js App

Copy the generated environment variables from `.env.aws` to your Next.js `.env.local`:

```bash
# From bootstrap output
WORKFLOW_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/...
WORKFLOW_STEP_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/...
WORKFLOW_RUNS_TABLE=workflow_runs
WORKFLOW_STEPS_TABLE=workflow_steps
WORKFLOW_EVENTS_TABLE=workflow_events
WORKFLOW_HOOKS_TABLE=workflow_hooks
WORKFLOW_STREAM_CHUNKS_TABLE=workflow_stream_chunks
WORKFLOW_STREAM_BUCKET=workflow-streams-...

# Add your AWS credentials
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
```

Add to your `next.config.ts`:

```typescript
import { withWorkflow } from 'workflow/next';

export default withWorkflow({
  experimental: {
    serverActions: {
      bodySizeLimit: '10mb',
    },
  },
});
```

### 4. Write Your First Workflow

Create `workflows/user-signup.ts`:

```typescript
import { sleep } from 'workflow';

export async function handleUserSignup(email: string) {
  'use workflow';

  // Step 1: Create user
  const user = await createUser(email);
  
  // Step 2: Send welcome email
  await sendWelcomeEmail(email);
  
  // Step 3: Wait 7 days (workflow suspends - no resources consumed!)
  await sleep('7 days');
  
  // Step 4: Send follow-up
  await sendFollowUpEmail(email);
  
  return { userId: user.id, status: 'completed' };
}

async function createUser(email: string) {
  'use step';
  // Your user creation logic
  return { id: '123', email };
}

async function sendWelcomeEmail(email: string) {
  'use step';
  // Send email via Resend, SendGrid, etc.
}

async function sendFollowUpEmail(email: string) {
  'use step';
  // Send follow-up email
}
```

### 5. Deploy to AWS Lambda

Whenever you add or update workflows, deploy them:

```bash
npm run deploy
```

**What this does:**
- Compiles your TypeScript workflows
- Builds Next.js to generate workflow bundles
- Packages Lambda handler with your workflows
- Deploys to AWS Lambda (no Docker required!)

### 6. Trigger Your Workflow

From your Next.js API route or Server Action:

```typescript
import { handleUserSignup } from '@/workflows/user-signup';

export async function POST(request: Request) {
  const { email } = await request.json();
  
  // Start the workflow
  const handle = await handleUserSignup(email);
  
  return Response.json({
    workflowId: handle.id,
    status: 'started'
  });
}
```

That's it! Your workflow is now running on AWS Lambda. 🚀

## Architecture

```
┌─────────────────┐
│   Next.js App   │
│  (Your Code)    │
└────────┬────────┘
         │
         │ Triggers workflow
         ▼
┌─────────────────┐      ┌──────────────┐
│   SQS Queues    │─────▶│ Lambda Worker│
│ (Orchestration) │      │ (Executes)   │
└─────────────────┘      └──────┬───────┘
                                │
                    ┌───────────┴───────────┐
                    │                       │
         ┌──────────▼────────┐   ┌─────────▼────────┐
         │   DynamoDB        │   │   S3 Bucket      │
         │ (State & Runs)    │   │ (Large Payloads) │
         └───────────────────┘   └──────────────────┘
```

## Key Features

### 🔄 Automatic Retries
Steps automatically retry on failure with exponential backoff.

### 💾 State Persistence
Workflow state is persisted to DynamoDB - resume from any point.

### ⏸️ Sleep & Wait
Use `sleep()` to pause workflows for minutes, hours, or days without consuming resources.

### 📊 Observability
Query workflow status, inspect step execution, view history:

```typescript
import { getWorkflowRun } from 'aws-workflow';

const run = await getWorkflowRun(workflowId);
console.log(run.status); // 'running' | 'completed' | 'failed'
```

### 🔀 Parallel Execution
Run multiple steps concurrently:

```typescript
export async function processOrder(orderId: string) {
  'use workflow';
  
  const [payment, inventory, shipping] = await Promise.all([
    processPayment(orderId),
    reserveInventory(orderId),
    calculateShipping(orderId),
  ]);
  
  return { payment, inventory, shipping };
}
```

## Commands

```bash
# Bootstrap AWS infrastructure (first time only)
npm run bootstrap

# Deploy workflows to Lambda
npm run deploy

# View Lambda logs in real-time
npm run logs

# Tear down all AWS resources
npm run teardown

# Get current AWS resource info
npm run outputs
```

## Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `WORKFLOW_QUEUE_URL` | SQS queue URL for workflow orchestration | ✅ |
| `WORKFLOW_STEP_QUEUE_URL` | SQS queue URL for step execution | ✅ |
| `WORKFLOW_RUNS_TABLE` | DynamoDB table for workflow runs | ✅ |
| `WORKFLOW_STEPS_TABLE` | DynamoDB table for step execution | ✅ |
| `WORKFLOW_STREAM_BUCKET` | S3 bucket for large payloads | ✅ |
| `AWS_REGION` | AWS region | ✅ |
| `AWS_ACCESS_KEY_ID` | AWS access key (local dev) | ✅* |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key (local dev) | ✅* |

*Not required when running on AWS (uses IAM roles)

### Cost Optimization

- Lambda executions are short-lived (typically <500ms per step)
- DynamoDB uses on-demand pricing (no upfront cost)
- SQS has free tier of 1M requests/month
- S3 is only used for payloads >256KB

**Typical monthly cost for moderate usage:** $5-20

## Limitations & Caveats

⚠️ **Beta Software Warnings:**

1. **API Stability**: APIs may change between versions
2. **Production Use**: Test thoroughly before production deployment
3. **Error Handling**: Custom error handling may be needed for edge cases
4. **Concurrent Execution**: Lambda concurrency limits apply (default: 1000)
5. **DynamoDB Limits**: Write capacity may need adjustment for high throughput
6. **Payload Size**: SQS messages limited to 256KB (larger payloads use S3)

## Troubleshooting

### Deployment fails with "Cannot find asset"
```bash
# Clean and rebuild
rm -rf cdk.out .next node_modules/.cache
npm run deploy
```

### Workflows not executing
```bash
# Check Lambda logs
npm run logs

# Verify environment variables
npm run outputs
```

### "Module not found" errors
Ensure your Next.js app uses npm (not pnpm) for flat `node_modules` structure:
```bash
rm -rf node_modules pnpm-lock.yaml
npm install
```

## Examples

Check out the [example Next.js app](./examples/nextjs-example) for a complete implementation including:
- User signup workflow with email sequence
- Multi-step ordering process
- Error handling and retries
- Webhook integrations

## Documentation

- [Workflow DevKit Docs](https://useworkflow.dev/docs)
- [API Reference](./docs/API.md)
- [Architecture Guide](./docs/ARCHITECTURE.md)
- [Migration Guide](./docs/MIGRATION.md)

## Contributing

Contributions are welcome! Please read our [Contributing Guide](./CONTRIBUTING.md) first.

## License

Apache-2.0 - see [LICENSE.md](./LICENSE.md)

---

Built with ❤️ by [Langtrace](https://langtrace.ai)

**GitHub:** [https://github.com/karthikscale3/aws-workflow](https://github.com/karthikscale3/aws-workflow)

**Part of the [Workflow DevKit](https://useworkflow.dev/) ecosystem**
