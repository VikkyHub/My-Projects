import { Body, Controller, Get, Module, Patch } from '@nestjs/common';
import { ApiBearerAuth, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { IsEmail, IsIn, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { AuthContext, CurrentUser } from '../../common/auth';
import { Database, InjectDb } from '../../infra/db/database';
import type { AppLanguage } from '../../infra/db/db.types';

class UpdateMeDto {
  @ApiPropertyOptional() @IsOptional() @IsString() @MinLength(2) @MaxLength(80) fullName?: string;
  @ApiPropertyOptional() @IsOptional() @IsEmail() email?: string;
  @ApiPropertyOptional({ enum: ['en', 'hi', 'mr'] }) @IsOptional() @IsIn(['en', 'hi', 'mr']) preferredLanguage?: AppLanguage;
}

@ApiTags('me')
@ApiBearerAuth()
@Controller('me')
export class MeController {
  constructor(@InjectDb() private readonly db: Database) {}

  @Get()
  async me(@CurrentUser() user: AuthContext) {
    const u = await this.db.selectFrom('users').select(['id', 'phone', 'email', 'fullName', 'avatarUrl', 'preferredLanguage', 'createdAt'])
      .where('id', '=', user.userId).executeTakeFirstOrThrow();
    const wallet = await this.db.selectFrom('wallets').select('balancePaise').where('userId', '=', user.userId).executeTakeFirst();
    return { ...u, walletBalancePaise: wallet?.balancePaise ?? 0 };
  }

  @Patch()
  async update(@CurrentUser() user: AuthContext, @Body() dto: UpdateMeDto) {
    if (Object.keys(dto).length) await this.db.updateTable('users').set(dto).where('id', '=', user.userId).execute();
    return this.me(user);
  }

  /** Shops this user can act for (vendor app shop switcher). */
  @Get('vendors')
  vendors(@CurrentUser() user: AuthContext) {
    return this.db.selectFrom('vendorMembers as m').innerJoin('vendors as v', 'v.id', 'm.vendorId')
      .select(['v.id as vendorId', 'v.businessName', 'v.status', 'v.logoUrl', 'm.role'])
      .where('m.userId', '=', user.userId).where('v.deletedAt', 'is', null).execute();
  }
}

@Module({ controllers: [MeController] })
export class MeModule {}
