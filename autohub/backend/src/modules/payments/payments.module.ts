import { Body, Controller, Get, Headers, HttpCode, Module, Param, ParseUUIDPipe, Post, Req, Res } from '@nestjs/common';
import { ApiBearerAuth, ApiExcludeEndpoint, ApiProperty, ApiTags } from '@nestjs/swagger';
import { IsString, Matches, MaxLength } from 'class-validator';
import type { Response } from 'express';
import { AppRequest, AuthContext, CurrentUser, Public } from '../../common/auth';
import { InjectRateLimiter, RateLimiter, enforceLimit } from '../../infra/ratelimit/rate-limiter';
import { PaymentsService } from './payments.service';

class VerifyPaymentDto {
  @ApiProperty({ example: 'order_PqR8…' }) @IsString() @MaxLength(64) @Matches(/^order_[A-Za-z0-9]+$/) razorpayOrderId: string;
  @ApiProperty({ example: 'pay_Ps2a…' }) @IsString() @MaxLength(64) @Matches(/^pay_[A-Za-z0-9]+$/) razorpayPaymentId: string;
  @ApiProperty() @IsString() @Matches(/^[a-f0-9]{64}$/) razorpaySignature: string;
}
class SimulateDto {
  @ApiProperty() @IsString() @Matches(/^order_[A-Za-z0-9]+$/) razorpayOrderId: string;
}

@ApiTags('payments')
@Controller()
export class PaymentsController {
  constructor(private readonly payments: PaymentsService, @InjectRateLimiter() private readonly rl: RateLimiter) {}

  @ApiBearerAuth() @Post('payments/verify')
  async verify(@CurrentUser() user: AuthContext, @Body() dto: VerifyPaymentDto, @Res({ passthrough: true }) res: Response) {
    await enforceLimit(this.rl, `pay-verify:${user.userId}`, 10, 60);
    const r = await this.payments.verify(user.userId, dto);
    res.status(r.status === 'authorized' ? 202 : 200);
    return r;
  }

  @ApiBearerAuth() @Get('payments/:id')
  status(@CurrentUser() user: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.payments.status(user.userId, id);
  }

  /** Razorpay → us. Signature over the raw body; must answer quickly. */
  @Public() @Post('webhooks/razorpay') @HttpCode(200) @ApiExcludeEndpoint()
  webhook(@Req() req: AppRequest, @Headers('x-razorpay-signature') sig?: string, @Headers('x-razorpay-event-id') eventId?: string) {
    return this.payments.handleWebhook(req.rawBody, sig, eventId);
  }

  /**
   * Local testing without a Razorpay account (RAZORPAY_MODE=fake): returns what Razorpay Checkout would return
   * after a successful UPI payment. Feed the result to POST /payments/verify. 404 in live mode.
   */
  @ApiBearerAuth() @Post('dev/payments/simulate') @HttpCode(200)
  simulate(@CurrentUser() _user: AuthContext, @Body() dto: SimulateDto) {
    return this.payments.simulate(dto.razorpayOrderId);
  }
}

@Module({ controllers: [PaymentsController], providers: [PaymentsService], exports: [PaymentsService] })
export class PaymentsModule {}
