# Next.js Example with aws-workflow

This is an example Next.js application demonstrating how to use [aws-workflow](https://github.com/karthikscale3/aws-workflow) with [Workflow DevKit](https://useworkflow.dev/).

## What's Included

This example demonstrates:

- ✅ **User Signup Workflow** - Multi-step workflow with email sequence
- ✅ **Durable Steps** - Steps that automatically retry on failure
- ✅ **Sleep/Delays** - Pause workflows for hours or days without consuming resources
- ✅ **Error Handling** - Graceful error handling with custom error types
- ✅ **API Integration** - Trigger workflows from Next.js API routes

## Project Structure

```
├── app/
│   ├── api/signup/route.ts          # API route to trigger workflows
│   └── page.tsx                      # Example UI
├── workflows/
│   └── user-signup.ts                # Example workflow definition
└── .env.local                        # Environment configuration
```

## Getting Started

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure AWS

Copy the environment variables from your aws-workflow bootstrap:

```bash
# .env.local
WORKFLOW_TARGET_WORLD=aws-workflow

# AWS credentials (for local development)
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key

# AWS resources (from bootstrap output)
WORKFLOW_AWS_WORKFLOW_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/...
WORKFLOW_AWS_STEP_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/...
WORKFLOW_AWS_RUNS_TABLE=workflow_runs
WORKFLOW_AWS_STEPS_TABLE=workflow_steps
WORKFLOW_AWS_EVENTS_TABLE=workflow_events
WORKFLOW_AWS_HOOKS_TABLE=workflow_hooks
WORKFLOW_AWS_STREAMS_TABLE=workflow_stream_chunks
WORKFLOW_AWS_STREAM_BUCKET=workflow-streams-...
```

### 3. Run Development Server

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser.

### 4. Trigger a Workflow

```bash
# Using the example UI at http://localhost:3000
# Or using curl:
curl -X POST http://localhost:3000/api/signup \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com"}'
```

### 5. Deploy to AWS Lambda

After making changes to workflows:

```bash
npm run deploy
```

This will:
1. Build your Next.js app
2. Generate workflow bundles
3. Deploy to AWS Lambda

## Example Workflow

See `workflows/user-signup.ts` for a complete example:

```typescript
export async function handleUserSignup(email: string) {
  'use workflow';

  // Step 1: Create user
  const user = await createUser(email);
  
  // Step 2: Send welcome email
  await sendWelcomeEmail(email);
  
  // Step 3: Wait 7 days (suspends, no resources used!)
  await sleep('7 days');
  
  // Step 4: Send follow-up
  await sendFollowUpEmail(email);
  
  return { userId: user.id, status: 'completed' };
}
```

## Key Features Demonstrated

### 🔄 Automatic Retries
Steps automatically retry on failure with exponential backoff.

### ⏸️ Sleep & Resume
Workflows can pause for minutes, hours, or days without consuming resources.

### 💾 State Persistence
All workflow state is persisted to DynamoDB - resume from any point.

### 🔀 Parallel Execution
Run multiple steps concurrently with `Promise.all()`.

### 🎯 Type Safety
Full TypeScript support with type inference.

## Learn More

- [Workflow DevKit Documentation](https://useworkflow.dev/docs)
- [aws-workflow GitHub](https://github.com/karthikscale3/aws-workflow)
- [Next.js Documentation](https://nextjs.org/docs)

## Deployment

### Deploy to Vercel (Frontend)

The Next.js app can be deployed to Vercel:

```bash
vercel
```

Make sure to add all environment variables to your Vercel project settings.

### Deploy to AWS Lambda (Workflows)

Workflows run on AWS Lambda:

```bash
npm run deploy
```
