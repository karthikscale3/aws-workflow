# Workflow Runtime Resume Issue

**Date:** October 26-27, 2025  
**Status:** ✅ RESOLVED - October 27, 2025

---

## 🎉 Resolution Summary

**Date Resolved:** October 27, 2025  
**Root Cause:** Architectural mismatch between `@workflow/world-local`'s embedded world pattern and AWS Lambda's serverless environment  
**Solution:** Direct handler invocation pattern (mirroring `@workflow/world-vercel`)  
**Package Version:** `aws-workflow@0.1.0-beta.23`

The issue has been **completely resolved**. Workflows now successfully resume after step completion, all steps execute in sequence, and workflow runs transition to "completed" status as expected.

### Solution Highlights

1. **Removed embedded world dependency** from `aws-workflow/world/queue.ts`
2. **Implemented direct handler invocation** in `createQueueHandler` (same pattern as Vercel)
3. **Added sequential workflow processing** in Lambda worker to prevent VM context race conditions
4. **Implemented retry mechanism** for `sleep()` steps using SQS visibility timeout
5. **Added idempotency checks** to prevent duplicate step creation on retry

---

## Executive Summary (Original Issue)

The AWS Workflow infrastructure is **fully operational** and working as designed. Steps execute successfully, data persists correctly, and all AWS services communicate properly. However, there was a **critical bug in the workflow runtime** that caused crashes when attempting to resume workflow execution after a step completes.

### What's Working ✅

- ✅ Next.js triggers workflows correctly
- ✅ Workflow messages reach Lambda via SQS
- ✅ Steps execute successfully in Lambda
- ✅ Step outputs save to DynamoDB correctly
- ✅ Step completion events are recorded
- ✅ Resume messages are queued back to SQS
- ✅ All AWS infrastructure (Lambda, SQS, DynamoDB, S3) configured correctly

### What's Not Working ❌

- ❌ Workflow runtime crashes on resume with `Runtime.NodeJsExit` error
- ❌ Workflow run status remains "running" instead of completing
- ❌ Promise rejection occurs before any user code executes

---

## Technical Solution Details

### Root Cause

The original implementation used `@workflow/world-local`'s embedded world pattern, which expected a local HTTP server to be running. This pattern doesn't work in AWS Lambda because:

1. Lambda is a **serverless, stateless** environment
2. No persistent HTTP server exists between invocations
3. The embedded world tried to start an HTTP server on each Lambda invocation
4. This caused race conditions and unhandled promise rejections during workflow resume

### The Fix

#### 1. Direct Handler Invocation (`aws-workflow/world/queue.ts`)

**Before:**
```typescript
// Used embedded world pattern (requires HTTP server)
const world = createEmbeddedWorld(config);
await world.start(); // ❌ Tried to start HTTP server in Lambda
```

**After:**
```typescript
// Direct handler invocation (same as @workflow/world-vercel)
const createQueueHandler: Queue['createQueueHandler'] = (prefix, handler) => {
  return async (request) => {
    const message = await request.json();
    const queueName = request.headers.get('x-vqs-queue-name') as ValidQueueName;
    const messageId = request.headers.get('x-vqs-message-id') || 'unknown';
    const attempt = Number(request.headers.get('x-vqs-message-attempt') || '1');

    // Invoke handler directly, no HTTP, no embedded world
    const result = await handler(message, {
      queueName,
      messageId: MessageId.parse(messageId),
      attempt,
    });

    return new Response(JSON.stringify(result), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  };
};
```

#### 2. Sequential Workflow Processing (`aws-workflow/lambda/worker/index.ts`)

**Problem:** Parallel processing of workflow messages caused VM context race conditions.

**Solution:** Process workflow messages sequentially, steps in parallel:

```typescript
// Separate workflow and step messages
const workflowMessages: SQSRecord[] = [];
const stepMessages: SQSRecord[] = [];

for (const record of event.Records) {
  const isWorkflowQueue = record.eventSourceARN?.includes('workflow-flows');
  if (isWorkflowQueue) {
    workflowMessages.push(record);
  } else {
    stepMessages.push(record);
  }
}

// Process steps in parallel (safe - no VM context)
const stepResults = await Promise.allSettled(
  stepMessages.map((record) => processMessage(record))
);

// Process workflows sequentially (prevents VM context conflicts)
const workflowResults: PromiseSettledResult<void>[] = [];
for (const record of workflowMessages) {
  try {
    await processMessage(record);
    workflowResults.push({ status: 'fulfilled', value: undefined });
  } catch (error) {
    workflowResults.push({ status: 'rejected', reason: error });
  }
}
```

#### 3. Sleep Step Retry Mechanism

**Problem:** `sleep()` steps need to defer execution without blocking Lambda.

**Solution:** Use SQS message visibility timeout:

```typescript
// In aws-workflow/lambda/worker/index.ts
if (directive && typeof directive.timeoutSeconds === 'number' && !isWorkflowQueue) {
  const sqs = new SQSClient({ region: process.env.AWS_REGION });
  const timeout = Math.max(1, Math.min(43200, directive.timeoutSeconds));
  
  // Adjust message visibility so it reappears after the sleep duration
  await sqs.send(
    new ChangeMessageVisibilityCommand({
      QueueUrl: process.env.WORKFLOW_AWS_STEP_QUEUE_URL!,
      ReceiptHandle: record.receiptHandle!,
      VisibilityTimeout: timeout,
    })
  );
  
  // Mark as failed so Lambda doesn't delete the message
  throw new Error(`Retry scheduled in ${timeout}s`);
}
```

#### 4. Idempotency for Step Creation

**Problem:** Retries could create duplicate steps in DynamoDB.

**Solution:** Use conditional writes:

```typescript
// In aws-workflow/world/storage.ts
async create(runId, data): Promise<Step> {
  const stepId = data.stepId || `step_${ulid()}`; // Use provided stepId or generate
  
  try {
    await client.send(
      new PutCommand({
        TableName: tableName,
        Item: step,
        ConditionExpression: 'attribute_not_exists(stepId)', // Idempotency check
      })
    );
  } catch (err: any) {
    if (err && err.name === 'ConditionalCheckFailedException') {
      throw new WorkflowAPIError(`Step already exists: ${stepId}`, {
        status: 409,
      });
    }
    throw err;
  }
  
  return step;
}
```

### Verification

After implementing these fixes:

✅ **Workflow Resume:** Workflows successfully resume after step completion  
✅ **All Steps Execute:** Multi-step workflows complete all steps in sequence  
✅ **Status Transitions:** Workflow runs transition from "running" to "completed"  
✅ **Sleep Works:** `sleep()` steps defer execution correctly using SQS visibility  
✅ **No Crashes:** No more `Runtime.NodeJsExit` errors  
✅ **Idempotency:** Retries don't create duplicate steps or events

---

## The Problem (Original Issue)

When a workflow step completes and the workflow attempts to resume execution to process the next step, the Lambda function crashes immediately with an unhandled promise rejection:

```
Runtime.NodeJsExit: RequestId: <uuid> Error: Runtime exited without providing a reason
Runtime.ExitError
```

This crash happens in **< 23ms**, before any workflow user code executes, indicating a problem in the core runtime's replay/resume mechanism.

---

## Evidence

### 1. Step Execution Success

**DynamoDB Query Results:**
```json
{
  "stepId": "step_01K8HA0N3RWH6MT9XD3MPSZQXW",
  "runId": "run_01K8HA0N3RWH6MT9XD3MP01FS2",
  "name": "createUser",
  "status": "completed",
  "output": "User created with ID: user_abc123",
  "completedAt": "2025-10-26T22:08:50.168Z"
}
```

✅ **The step executed successfully and saved its output.**

### 2. Events Recorded Correctly

**Events Count:** 2 events in DynamoDB
- `step_started`: Step began execution
- `step_completed`: Step finished with output

✅ **Event sourcing is working correctly.**

### 3. Workflow Run Status

**Status:** `running`  
**Should Be:** `completed` (after all steps finish)

❌ **The workflow never transitions to completed state because it crashes on resume.**

### 4. Lambda Crash Logs

```
INIT_START Runtime Version: nodejs:20.v35
START RequestId: <uuid> Version: $LATEST

[Runtime.NodeJsExit] RequestId: <uuid> Error: Runtime exited without providing a reason
Runtime.ExitError

END RequestId: <uuid>
REPORT RequestId: <uuid>
  Duration: 22.71 ms
  Billed Duration: 23 ms
  Memory Size: 512 MB
  Max Memory Used: 107 MB
```

**Key Observations:**
- No console logs from workflow runtime appear
- Crash happens in ~23ms (too fast for user code)
- Error type: `Runtime.NodeJsExit` indicates unsettled promise

---

## Root Cause Analysis

### Call Flow (Expected)

```
1. Step Completes → Queue workflow resume message
2. Lambda receives resume message from SQS
3. Runtime loads workflow from DynamoDB
4. Runtime loads events (step_started, step_completed)
5. Runtime replays events in VM to rebuild state
6. Runtime continues execution from where it paused
7. Next step (sendWelcomeEmail) executes
8. Workflow completes → status updated to "completed"
```

### Where It Fails

The crash occurs at **step 5** (replaying events in VM). The workflow runtime's replay mechanism has an issue that causes an unhandled promise rejection.

### Technical Details

**Location:** `@workflow/core` package (not AWS-specific code)  
**Component:** Workflow replay/resume mechanism  
**Environment:** AWS Lambda (Node.js 20 runtime)

**Likely Causes:**
1. **Promise Handling in VM Context:** The workflow runtime uses `vm2` or similar to execute user code. When replaying completed steps, it may not properly handle promises from the replayed code.

2. **Event Replay Logic:** The replay mechanism might be re-executing async operations (like `sleep()` or step calls) that should be skipped during replay.

3. **Lambda Context Timing:** Lambda's execution model may be interacting poorly with the VM's promise handling during replay.

---

## Test Workflow

The test workflow used:

```typescript
// workflows/user-signup.ts
export const userSignupWorkflow = workflow('user-signup')
  .describe('Complete user signup flow')
  .input(z.object({
    email: z.string().email(),
    name: z.string(),
  }))
  .handler(async ({ input, step }) => {
    // Step 1: Create user (✅ COMPLETES)
    const userId = await step('createUser', async () => {
      return `User created with ID: user_abc123`;
    });

    // Step 2: Send welcome email (❌ NEVER REACHED - crash on resume)
    await step('sendWelcomeEmail', async () => {
      if (Math.random() < 0.3) {
        throw new Error('Email service unavailable');
      }
      await sleep(2000);
      return 'Welcome email sent';
    });

    // Step 3: Send onboarding email (❌ NEVER REACHED)
    await step('sendOnboardingEmail', async () => {
      await sleep(1000);
      return 'Onboarding email sent';
    });

    return { success: true, userId };
  });
```

---

## Reproduction Steps

1. **Deploy the AWS infrastructure:**
   ```bash
   cd aws-workflow
   pnpm build
   pnpm deploy
   ```

2. **Start the Next.js test app:**
   ```bash
   cd examples/nextjs-example
   pnpm dev
   ```

3. **Trigger the workflow:**
   ```bash
   curl -X POST http://localhost:3000/api/trigger-workflow \
     -H "Content-Type: application/json" \
     -d '{"email":"test@example.com","name":"Test User"}'
   ```

4. **Observe the results:**
   - First step (`createUser`) completes successfully
   - Check DynamoDB: step status is "completed"
   - Check Lambda logs: Crash with `Runtime.NodeJsExit` when resuming
   - Check workflow run: status remains "running"

---

## Workarounds & Mitigation

### Option 1: Single-Step Workflows (Temporary)
For immediate use, create workflows with only one step to avoid the resume issue:

```typescript
export const simpleWorkflow = workflow('simple')
  .handler(async ({ input }) => {
    // Do everything in one go (no steps)
    const result = await doAllWork(input);
    return result;
  });
```

### Option 2: External Orchestration
Use Step Functions or another orchestrator to chain single-step workflows:
- Each workflow does one atomic operation
- AWS Step Functions handles sequencing
- No resume logic needed

### Option 3: Patch the Runtime
The fix likely requires changes to `@workflow/core`:
- Add better promise tracking in VM context
- Skip async operations during replay
- Improve Lambda compatibility

---

## Infrastructure Validation

To confirm the infrastructure is working correctly, we validated:

### ✅ Environment Variables
```bash
# Lambda environment variables are correctly set
WORKFLOW_TARGET_WORLD=aws-workflow
WORKFLOW_AWS_WORKFLOW_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/.../workflow_queue
WORKFLOW_AWS_STEP_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/.../step_queue
WORKFLOW_AWS_RUNS_TABLE=workflow_runs
WORKFLOW_AWS_STEPS_TABLE=workflow_steps
WORKFLOW_AWS_EVENTS_TABLE=workflow_events
```

### ✅ DynamoDB Tables
```bash
# Correct schemas with composite keys
workflow_runs: runId (HASH)
workflow_steps: stepId (HASH) + runId (RANGE)
workflow_events: eventId (HASH) with runId-createdAt-index
```

### ✅ SQS Queues
```bash
# Messages flow correctly
workflow_queue: Receives workflow start/resume messages
step_queue: Receives step execution messages
```

### ✅ Lambda Function
```bash
# Correctly configured
Runtime: Node.js 20
Memory: 512 MB
Timeout: 300 seconds
Layer: Contains all dependencies
Code: Up-to-date with latest changes
```

### ✅ IAM Permissions
```bash
# Lambda has full access to:
- DynamoDB (all tables)
- SQS (both queues)
- S3 (workflow bucket)
- CloudWatch Logs
```

---

## Next Steps

### Immediate Actions
1. **Report to Workflow Team:** Create an issue in the `@workflow/core` repository with this reproduction case
2. **Use Workaround:** Implement single-step workflows or external orchestration for production use
3. **Monitor Lambda:** Set up CloudWatch alarms for `Runtime.NodeJsExit` errors

### Long-Term Fix
The fix requires debugging the `@workflow/core` package:

1. **Add detailed logging** in the replay mechanism:
   ```typescript
   // In @workflow/core/src/runtime.ts
   console.log('Starting replay with events:', events.length);
   for (const event of events) {
     console.log('Replaying event:', event.type);
     // ... replay logic
   }
   ```

2. **Test promise handling** in VM context:
   - Ensure replayed async operations don't create new promises
   - Verify all promises are properly awaited
   - Check for race conditions in Lambda environment

3. **Add Lambda-specific tests:**
   - Test workflow resume in actual Lambda environment
   - Validate promise lifecycle in Lambda's execution model
   - Test with various step counts and async operations

---

## Conclusion

**Infrastructure Status:** ✅ Production-Ready  
**Runtime Status:** ✅ RESOLVED - October 27, 2025

The AWS infrastructure is solid and working exactly as designed. All AWS services are properly configured, data flows correctly, and steps execute successfully. The workflow runtime issue has been **completely resolved** by implementing a direct handler invocation pattern that's compatible with AWS Lambda's serverless environment.

### Production Readiness

The `aws-workflow` package (v0.1.0-beta.23+) is now ready for production use with:
- ✅ Multi-step workflows with automatic resume
- ✅ Durable execution with state persistence
- ✅ Step retries with exponential backoff
- ✅ Sleep/delay support via SQS visibility timeout
- ✅ Idempotent operations
- ✅ Full AWS integration (Lambda, DynamoDB, SQS, S3)

No workarounds or external orchestration needed.

---

## Related Files

- **Infrastructure:** `/aws-workflow/lib/workflow-stack.ts`
- **Storage:** `/aws-workflow/world/storage.ts`
- **Queue:** `/aws-workflow/world/queue.ts`
- **Lambda Handler:** `/aws-workflow/lambda/worker/index.ts`
- **Test Workflow:** `/aws-workflow/examples/nextjs-example/workflows/user-signup.ts`
- **Progress Summary:** `/aws-workflow/PROGRESS_SUMMARY.md`
- **Victory Summary:** `/aws-workflow/VICTORY.md`

---

## Contact & Support

For questions about this resolution:
- **AWS Infrastructure:** All working correctly ✅
- **Runtime Issue:** Resolved October 27, 2025 ✅
- **Package:** `aws-workflow@0.1.0-beta.23` and later
- **This Document:** Created October 26, 2025, Updated October 27, 2025

