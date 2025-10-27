export async function register() {
  // The world will be auto-discovered by Workflow SDK based on WORKFLOW_TARGET_WORLD env var
  // Set WORKFLOW_TARGET_WORLD=aws-workflow in .env.local

  // ⚠️ DO NOT start queue workers in Next.js!
  // The Lambda function deployed via CDK handles queue processing.
  // Next.js only uses direct API methods (runs.create, steps.update, etc.)

  if (process.env.NEXT_RUNTIME !== 'edge') {
    console.log('✅ Workflow initialized with AWS backend');
    console.log(
      `   Target world: ${process.env.WORKFLOW_TARGET_WORLD || 'not set'}`
    );
  }
}
