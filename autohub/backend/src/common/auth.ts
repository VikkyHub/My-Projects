import {
  CanActivate, createParamDecorator, ExecutionContext, Injectable, SetMetadata,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import type { Request } from 'express';
import { Database, InjectDb } from '../infra/db/database';
import type { AdminRole, ClientApp, VendorMemberRole, VendorStatus } from '../infra/db/db.types';
import { Errors } from './errors';

export interface AuthContext { userId: string; app: ClientApp; sessionId: string; adminRole: AdminRole | null }
export interface VendorContext { id: string; role: VendorMemberRole; status: VendorStatus }
export interface AccessTokenClaims { sub: string; app: ClientApp; sid: string }
export type AppRequest = Request & { id?: string; auth?: AuthContext; vendor?: VendorContext; rawBody?: Buffer };

const PUBLIC = 'auth:public';
const ADMIN_ROLES = 'auth:adminRoles';
const VENDOR_ROLE = 'auth:vendorRole';
const VENDOR_ANY_STATUS = 'auth:vendorAnyStatus';

/** No token needed. If a valid token is sent anyway, the user is attached (e.g. to personalise fitment). */
export const Public = () => SetMetadata(PUBLIC, true);
/** Admin app only; super_admin is always allowed. */
export const AdminOnly = (...roles: AdminRole[]) => SetMetadata(ADMIN_ROLES, roles);
/** Requires X-Vendor-Id and membership with at least `role` (staff < manager < owner). */
export const VendorRole = (role: VendorMemberRole) => SetMetadata(VENDOR_ROLE, role);
/** Allow vendors that are not approved yet (onboarding screens). */
export const AllowUnapprovedVendor = () => SetMetadata(VENDOR_ANY_STATUS, true);

export const CurrentUser = createParamDecorator((_: unknown, ctx: ExecutionContext): AuthContext => {
  const auth = ctx.switchToHttp().getRequest<AppRequest>().auth;
  if (!auth) throw Errors.unauthenticated();
  return auth;
});
export const OptionalUser = createParamDecorator(
  (_: unknown, ctx: ExecutionContext): AuthContext | undefined => ctx.switchToHttp().getRequest<AppRequest>().auth,
);
export const CurrentVendor = createParamDecorator((_: unknown, ctx: ExecutionContext): VendorContext => {
  const vendor = ctx.switchToHttp().getRequest<AppRequest>().vendor;
  if (!vendor) throw Errors.forbidden('Vendor context missing');
  return vendor;
});

const ROLE_RANK: Record<VendorMemberRole, number> = { staff: 1, manager: 2, owner: 3 };
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Global guard, runs on every request:
 *  1. verifies the JWT and that the session is live and the user active (so logout/suspension is immediate)
 *  2. checks the token was issued to the app named in X-Client-App
 *  3. enforces admin roles and vendor membership when the route asks for them
 */
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly jwt: JwtService,
    @InjectDb() private readonly db: Database,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const targets = [ctx.getHandler(), ctx.getClass()];
    const isPublic = this.reflector.getAllAndOverride<boolean>(PUBLIC, targets) ?? false;
    const req = ctx.switchToHttp().getRequest<AppRequest>();

    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      if (isPublic) return true;
      throw Errors.unauthenticated();
    }
    try {
      req.auth = await this.authenticate(header.slice(7), req);
    } catch (e) {
      if (isPublic) return true;       // a stale token never blocks public browsing
      throw e;
    }
    if (isPublic) return true;

    const adminRoles = this.reflector.getAllAndOverride<AdminRole[]>(ADMIN_ROLES, targets);
    if (adminRoles) {
      const role = req.auth.adminRole;
      if (req.auth.app !== 'admin' || !role || (role !== 'super_admin' && !adminRoles.includes(role))) throw Errors.forbidden();
    }

    const vendorRole = this.reflector.getAllAndOverride<VendorMemberRole>(VENDOR_ROLE, targets);
    if (vendorRole) {
      if (req.auth.app !== 'vendor') throw Errors.forbidden('Use the vendor app for this.');
      const vendorId = req.header('x-vendor-id') ?? '';
      if (!UUID_RE.test(vendorId)) throw Errors.forbidden('X-Vendor-Id header is required.');
      const m = await this.db.selectFrom('vendorMembers as m').innerJoin('vendors as v', 'v.id', 'm.vendorId')
        .select(['v.id', 'v.status', 'm.role'])
        .where('m.vendorId', '=', vendorId).where('m.userId', '=', req.auth.userId).where('v.deletedAt', 'is', null)
        .executeTakeFirst();
      if (!m || ROLE_RANK[m.role] < ROLE_RANK[vendorRole]) throw Errors.forbidden();
      const anyStatus = this.reflector.getAllAndOverride<boolean>(VENDOR_ANY_STATUS, targets) ?? false;
      if (!anyStatus && m.status !== 'approved') throw Errors.forbidden('Your shop is not approved yet.');
      req.vendor = { id: m.id, role: m.role, status: m.status };
    } else if (!adminRoles && req.auth.app === 'admin') {
      // Admin tokens are only for /admin routes.
      throw Errors.forbidden();
    }
    return true;
  }

  private async authenticate(token: string, req: AppRequest): Promise<AuthContext> {
    let claims: AccessTokenClaims;
    try {
      claims = await this.jwt.verifyAsync<AccessTokenClaims>(token, { algorithms: ['HS256'] });
    } catch (e) {
      throw (e as Error).name === 'TokenExpiredError' ? Errors.tokenExpired() : Errors.unauthenticated();
    }
    const clientApp = req.header('x-client-app');
    if (clientApp && clientApp !== claims.app) throw Errors.unauthenticated('Token was issued to a different app.');

    const row = await this.db.selectFrom('userSessions as s').innerJoin('users as u', 'u.id', 's.userId')
      .select(['u.status', 'u.adminRole', 's.revokedAt'])
      .where('s.id', '=', claims.sid).where('s.userId', '=', claims.sub)
      .executeTakeFirst();
    if (!row || row.revokedAt || row.status !== 'active') throw Errors.unauthenticated();
    return { userId: claims.sub, app: claims.app, sessionId: claims.sid, adminRole: row.adminRole };
  }
}
