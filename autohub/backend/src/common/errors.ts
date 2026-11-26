import {
  ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger,
} from '@nestjs/common';
import type { Request, Response } from 'express';

/** Business error with a stable machine-readable code (see docs/03-api-spec.md §1.5). */
export class AppError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly details?: Record<string, unknown>,
  ) {
    super(message);
  }
}

export const Errors = {
  validation: (fields: Record<string, string>) => new AppError(400, 'VALIDATION_FAILED', 'Some fields are invalid.', { fields }),
  unauthenticated: (msg = 'Please log in again.') => new AppError(401, 'UNAUTHENTICATED', msg),
  tokenExpired: () => new AppError(401, 'TOKEN_EXPIRED', 'Session expired.'),
  forbidden: (msg = 'You do not have access to this.') => new AppError(403, 'FORBIDDEN', msg),
  notFound: (what = 'Resource') => new AppError(404, 'NOT_FOUND', `${what} not found.`),
  conflict: (code: string, msg: string, details?: Record<string, unknown>) => new AppError(409, code, msg, details),
  rule: (code: string, msg: string, details?: Record<string, unknown>) => new AppError(422, code, msg, details),
  rateLimited: (retryAfterSeconds: number) =>
    new AppError(429, 'RATE_LIMITED', `Too many requests. Try again in ${retryAfterSeconds} seconds.`, { retryAfterSeconds }),
  invalidTransition: (from: string, action: string, allowed: string[]) =>
    new AppError(409, 'INVALID_STATE_TRANSITION', `Cannot ${action} when status is ${from}.`, { from, allowed }),
};

const PG_UNIQUE = '23505';
const PG_CHECK = '23514';
const PG_FK = '23503';

@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly log = new Logger('Error');

  catch(err: unknown, host: ArgumentsHost) {
    const res = host.switchToHttp().getResponse<Response>();
    const req = host.switchToHttp().getRequest<Request & { id?: string }>();
    const requestId = req.id;
    const send = (status: number, code: string, message: string, details?: unknown) => {
      if (status === 429 && details && typeof details === 'object' && 'retryAfterSeconds' in details) {
        res.setHeader('Retry-After', String((details as { retryAfterSeconds: number }).retryAfterSeconds));
      }
      res.status(status).json({ error: { code, message, ...(details ? { details } : {}), requestId } });
    };

    if (err instanceof AppError) return send(err.status, err.code, err.message, err.details);

    if (err instanceof HttpException) {
      const status = err.getStatus();
      const body = err.getResponse() as { message?: unknown };
      if (status === HttpStatus.BAD_REQUEST && Array.isArray(body?.message)) {
        return send(400, 'VALIDATION_FAILED', 'Some fields are invalid.', { fields: body.message });
      }
      const code = status === 404 ? 'NOT_FOUND' : status === 401 ? 'UNAUTHENTICATED' : status === 403 ? 'FORBIDDEN' : 'HTTP_ERROR';
      return send(status, code, typeof body?.message === 'string' ? body.message : err.message);
    }

    // Constraint violations that slipped past service-level checks: report, never leak SQL.
    const pg = err as { code?: string; constraint?: string };
    if (pg?.code === PG_UNIQUE) return send(409, 'CONFLICT', 'This already exists.', { constraint: pg.constraint });
    if (pg?.code === PG_CHECK || pg?.code === PG_FK) {
      return send(422, 'CONSTRAINT_VIOLATION', 'The request breaks a data rule.', { constraint: pg.constraint });
    }

    this.log.error({ requestId, err }, (err as Error)?.stack);
    return send(500, 'INTERNAL', 'Something went wrong. Please try again.');
  }
}
