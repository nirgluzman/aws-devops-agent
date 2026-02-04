/**
 * AWS Lambda function to handle S3 bucket operations for messages
 * @param {Object} event - API Gateway event object
 * @param {Object} event.requestContext - Request context containing HTTP method
 * @param {string} event.body - Request body for POST requests
 * @returns {Object} Response object with statusCode and body
 *
 * Supports:
 * - GET: Lists all messages stored in S3 bucket
 * - POST: Stores new message in S3 bucket with timestamp
 *
 * Environment variables required:
 * - AWS_REGION: AWS region (defaults to us-east-1)
 * - MESSAGES_BUCKET: S3 bucket name for message storage
 */

import { S3Client, ListObjectsV2Command, PutObjectCommand } from '@aws-sdk/client-s3';
import { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from 'aws-lambda';

// Opinionated wrapper for AWS X-Ray tracing
import { Tracer } from '@aws-lambda-powertools/tracer';
import { captureLambdaHandler } from '@aws-lambda-powertools/tracer/middleware';

// Middleware to wrap the handler for pre/post-processing
import middy from '@middy/core';

// Utility to generate unique, random IDs for resources
import { v4 } from 'uuid';

// Environment variables
const awsRegion = process.env.AWS_REGION || 'us-east-1';
const bucketName = process.env.MESSAGES_BUCKET;

// Initialize X-Ray tracer
const tracer = new Tracer({ serviceName: 'handle_messages' });

// Wrap the S3 client so every S3 API call automatically appears as a subsegment in X-Ray
// Without it: we'd only see the Lambda invocation segment — no visibility into what the Lambda is doing internally
const client = tracer.captureAWSv3Client(new S3Client({ region: awsRegion }));

const lambdaHandler = async (event: APIGatewayProxyEventV2): Promise<APIGatewayProxyResultV2> => {
  console.log('Received event:', JSON.stringify(event, null, 2));

  const method = event.requestContext.http.method;

  // Handle GET request - List objects in the S3 bucket
  if (method === 'GET') {
    const subsegment = tracer.provider.getSegment()!.addNewSubsegment('S3-ListObjects');
    try {
      const command = new ListObjectsV2Command({
        Bucket: bucketName,
        Prefix: 'messages/',
        Delimiter: '/',
      });
      const response = await client.send(command);
      const objectList = response.Contents ? response.Contents.map((obj) => obj.Key) : [];
      subsegment.close();
      return {
        statusCode: 200,
        body: JSON.stringify({ message: 'Messages retrieved successfully', data: objectList }),
      };
    } catch (error) {
      subsegment.addError(error as Error);
      subsegment.close();
      throw error;
    }
  }

  // Handle POST request - Store a message in S3 bucket
  else if (method === 'POST') {
    if (!event.body) {
      return {
        statusCode: 400,
        body: JSON.stringify({ message: 'Bad Request: Missing request body' }),
      };
    }
    const body = JSON.parse(event.body);

    const subsegment = tracer.provider.getSegment()!.addNewSubsegment('S3-PutObject');
    try {
      const command = new PutObjectCommand({
        Bucket: bucketName,
        Key: `messages/${Date.now()}-${v4()}.json`,
        Body: JSON.stringify(body),
      });
      await client.send(command);
      subsegment.close();
      return {
        statusCode: 200,
        body: JSON.stringify({ message: 'Message processed successfully' }),
      };
    } catch (error) {
      subsegment.addError(error as Error);
      subsegment.close();
      throw error;
    }
  }

  // Handle unsupported methods
  else {
    return {
      statusCode: 405,
      body: JSON.stringify({ message: 'Method Not Allowed' }),
    };
  }
};

export const handler = middy(lambdaHandler).use(captureLambdaHandler(tracer));
