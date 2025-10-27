import { handleUserSignup } from '@/workflows/user-signup';
import { NextResponse } from 'next/server';
import { start } from 'workflow/api';

export async function POST(request: Request) {
  const { email } = await request.json();

  // Executes asynchronously and doesn't block your app
  await start(handleUserSignup, [email]);

  return NextResponse.json({
    message: 'User signup workflow started',
  });
}
