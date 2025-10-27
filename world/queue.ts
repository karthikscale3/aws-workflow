import {
  DeleteMessageCommand,
  ReceiveMessageCommand,
  SendMessageCommand,
  type SQSClient,
} from '@aws-sdk/client-sqs';
import { JsonTransport } from '@vercel/queue';
import {
  MessageId,
  QueuePayloadSchema,
  type Queue,
  type QueuePrefix,
  type ValidQueueName,
} from '@workflow/world';
import { createEmbeddedWorld } from '@workflow/world-local';
import { monotonicFactory } from 'ulid';
import type { AWSWorldConfig } from './config.js';

function parseQueueName(queueName: ValidQueueName): [QueuePrefix, string] {
  // Queue names are like: __wkf_workflow_someId or __wkf_step_someId
  if (queueName.startsWith('__wkf_workflow_')) {
    return ['__wkf_workflow_', queueName.slice('__wkf_workflow_'.length)];
  } else if (queueName.startsWith('__wkf_step_')) {
    return ['__wkf_step_', queueName.slice('__wkf_step_'.length)];
  }
  throw new Error(`Invalid queue name format: ${queueName}`);
}

export function createQueue(
  client: SQSClient,
  config: AWSWorldConfig
): Queue & { start(): Promise<void> } {
  const port = process.env.PORT ? Number(process.env.PORT) : undefined;
  const embeddedWorld = createEmbeddedWorld({ dataDir: undefined, port });

  const transport = new JsonTransport();
  const generateMessageId = monotonicFactory();

  const Queues = {
    __wkf_workflow_: config.queues.workflow,
    __wkf_step_: config.queues.step,
  } as const satisfies Record<QueuePrefix, string>;

  const createQueueHandler = embeddedWorld.createQueueHandler;

  const getDeploymentId: Queue['getDeploymentId'] = async () => {
    return 'aws';
  };

  const queue: Queue['queue'] = async (queue, message, opts) => {
    const [prefix, queueId] = parseQueueName(queue);
    const queueUrl = Queues[prefix];

    console.log('🔍 Queueing message:', { queue, prefix, queueId, queueUrl });

    if (!queueUrl) {
      throw new Error(
        `Queue URL not found for prefix: ${prefix}. Available: ${Object.keys(
          Queues
        ).join(', ')}`
      );
    }

    const body = transport.serialize(message);
    const messageId = MessageId.parse(`msg_${generateMessageId()}`);

    console.log('📤 Sending to SQS:', {
      queueUrl,
      messageId,
      isFifo: queueUrl.endsWith('.fifo'),
    });

    // Convert Buffer to base64 to avoid JSON serialization issues
    const dataBase64 = body.toString('base64');

    await client.send(
      new SendMessageCommand({
        QueueUrl: queueUrl,
        MessageBody: JSON.stringify({
          id: queueId,
          data: dataBase64,
          attempt: 1,
          messageId,
          idempotencyKey: opts?.idempotencyKey,
        }),
        // FIFO parameters only if queue URL ends with .fifo
        ...(queueUrl?.endsWith('.fifo')
          ? {
              MessageDeduplicationId: opts?.idempotencyKey ?? messageId,
              MessageGroupId: queueId,
            }
          : {}),
      })
    );

    console.log('✅ Message queued successfully');
    return { messageId };
  };

  let isStarted = false;
  let shouldStop = false;

  async function pollQueue(queueUrl: string, queuePrefix: QueuePrefix) {
    while (!shouldStop) {
      try {
        const response = await client.send(
          new ReceiveMessageCommand({
            QueueUrl: queueUrl,
            MaxNumberOfMessages: 1,
            WaitTimeSeconds: 20, // Long polling
            VisibilityTimeout: 300, // 5 minutes
          })
        );

        if (!response.Messages || response.Messages.length === 0) {
          continue;
        }

        for (const message of response.Messages) {
          if (!message.Body || !message.ReceiptHandle) continue;

          try {
            const body = JSON.parse(message.Body);
            const payload = QueuePayloadSchema.parse(
              transport.deserialize(body.data)
            );

            // Create a queue name to pass to the embedded world
            const queueName: ValidQueueName = `${queuePrefix}${body.id}`;

            // Use the embedded world's queue handler
            const handler = createQueueHandler(
              queuePrefix,
              async (msg, meta) => {
                // The embedded world will handle the actual workflow/step execution
              }
            );

            // Make an HTTP request to the embedded world
            const request = new Request(
              `http://localhost:${port || 3000}/.well-known/workflow/v1/${
                queuePrefix === '__wkf_workflow_' ? 'flow' : 'step'
              }`,
              {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                  message: payload,
                  meta: {
                    attempt: body.attempt || 1,
                    queueName,
                    messageId: body.messageId,
                  },
                }),
              }
            );

            const response = await handler(request);

            if (response.status === 200) {
              // Delete message from queue on success
              await client.send(
                new DeleteMessageCommand({
                  QueueUrl: queueUrl,
                  ReceiptHandle: message.ReceiptHandle,
                })
              );
            } else {
              // Message will become visible again after visibility timeout
              console.error(`Queue handler returned status ${response.status}`);
            }
          } catch (error) {
            console.error('Error processing message:', error);
            // Message will become visible again after visibility timeout
          }
        }
      } catch (error) {
        console.error('Error polling queue:', error);
        // Wait a bit before retrying
        await new Promise((resolve) => setTimeout(resolve, 5000));
      }
    }
  }

  async function start() {
    if (isStarted) return;
    isStarted = true;
    shouldStop = false;

    // Start polling both queues
    Promise.all([
      pollQueue(Queues.__wkf_workflow_, '__wkf_workflow_'),
      pollQueue(Queues.__wkf_step_, '__wkf_step_'),
    ]).catch((error) => {
      console.error('Queue polling error:', error);
    });
  }

  return {
    getDeploymentId,
    queue,
    createQueueHandler:
      createQueueHandler as unknown as Queue['createQueueHandler'],
    start,
  };
}
