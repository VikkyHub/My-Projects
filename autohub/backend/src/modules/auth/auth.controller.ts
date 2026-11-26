import { Body, Controller, HttpCode, Module, Post, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsIn, IsOptional, IsString, IsUUID, Length, Matches, MaxLength, ValidateNested } from 'class-validator';
import { AppRequest, AuthContext, CurrentUser, Public } from '../../common/auth';
import { Errors } from '../../common/errors';
import type { ClientApp } from '../../infra/db/db.types';
import { AuthService } from './auth.service';

const E164 = /^\+[1-9][0-9]{7,14}$/;

class OtpRequestDto {
  @ApiProperty({ example: '+919000000001' }) @Matches(E164, { message: 'phone must be E.164, e.g. +919876543210' })
  phone: string;
}

class DeviceDto {
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(100) deviceId?: string;
  @ApiPropertyOptional({ enum: ['android', 'ios', 'web'] }) @IsOptional() @IsIn(['android', 'ios', 'web']) platform?: 'android' | 'ios' | 'web';
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(30) appVersion?: string;
}

class OtpVerifyDto {
  @ApiProperty() @IsUUID() otpRequestId: string;
  @ApiProperty({ example: '+919000000001' }) @Matches(E164) phone: string;
  @ApiProperty({ example: '123456' }) @Length(6, 6) @Matches(/^[0-9]{6}$/) code: string;
  @ApiPropertyOptional({ type: DeviceDto }) @IsOptional() @ValidateNested() @Type(() => DeviceDto) device?: DeviceDto;
}

class RefreshDto {
  @ApiProperty() @IsString() @MaxLength(200) refreshToken: string;
}

function clientApp(req: AppRequest): ClientApp {
  const app = req.header('x-client-app');
  if (app !== 'customer' && app !== 'vendor' && app !== 'admin') {
    throw Errors.validation({ 'X-Client-App': 'header must be customer, vendor or admin' });
  }
  return app;
}

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Public() @Post('otp/request') @HttpCode(200)
  request(@Body() dto: OtpRequestDto, @Req() req: AppRequest) {
    return this.auth.requestOtp(dto.phone, req.ip);
  }

  @Public() @Post('otp/verify') @HttpCode(200)
  verify(@Body() dto: OtpVerifyDto, @Req() req: AppRequest) {
    return this.auth.verifyOtp({
      ...dto, app: clientApp(req), device: dto.device ?? {}, ip: req.ip, userAgent: req.header('user-agent'),
    });
  }

  @Public() @Post('refresh') @HttpCode(200)
  refresh(@Body() dto: RefreshDto) {
    return this.auth.refresh(dto.refreshToken);
  }

  @ApiBearerAuth() @Post('logout') @HttpCode(204)
  async logout(@CurrentUser() user: AuthContext) {
    await this.auth.logout(user.sessionId);
  }

  @ApiBearerAuth() @Post('logout-all') @HttpCode(204)
  async logoutAll(@CurrentUser() user: AuthContext) {
    await this.auth.logoutAll(user.userId);
  }
}

@Module({ controllers: [AuthController], providers: [AuthService] })
export class AuthModule {}
