import 'express';

declare module 'express' {
  interface Request {
    user?: {
      id: number;
      username: string;
      email?: string;
      role: string;
    };
    requestId?: string;
    activityLogged?: boolean;
  }
}
