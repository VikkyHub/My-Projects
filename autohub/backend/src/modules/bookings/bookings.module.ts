import { Body, Controller, Get, Headers, HttpCode, Module, OnModuleInit, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiHeader, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize, ArrayMinSize, IsArray, IsBoolean, IsIn, IsInt, IsNumber, IsOptional, IsString, IsUrl, IsUUID, Matches,
  Max, MaxLength, Min, ValidateNested,
} from 'class-validator';
import { AuthContext, CurrentUser, CurrentVendor, VendorContext, VendorRole } from '../../common/auth';
import { Errors } from '../../common/errors';
import type { BookingStatus, LineKind, ServiceLocation } from '../../infra/db/db.types';
import { PaymentsModule } from '../payments/payments.module';
import { PaymentsService } from '../payments/payments.service';
import { BookingsService } from './bookings.service';

const UUID_V4ISH = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

class AttachmentDto {
  @ApiProperty({ enum: ['issue_photo'] }) @IsIn(['issue_photo']) kind: 'issue_photo';
  @ApiProperty() @IsString() @MaxLength(200) publicId: string;
  @ApiProperty() @IsUrl({ protocols: ['https'], require_protocol: true }) url: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(200) caption?: string;
}
class CreateBookingDto {
  @ApiProperty() @IsUUID() vendorId: string;
  @ApiProperty() @IsUUID() vehicleId: string;
  @ApiProperty({ type: [String] }) @IsArray() @ArrayMinSize(1) @ArrayMaxSize(10) @IsUUID('all', { each: true }) serviceIds: string[];
  @ApiProperty() @IsUUID() slotId: string;
  @ApiPropertyOptional({ enum: ['at_shop', 'doorstep', 'pickup_drop'] }) @IsOptional() @IsIn(['at_shop', 'doorstep', 'pickup_drop']) locationType?: ServiceLocation;
  @ApiPropertyOptional() @IsOptional() @IsUUID() addressId?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(1000) customerNotes?: string;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(0) odometerKm?: number;
  @ApiPropertyOptional({ default: true }) @IsOptional() @IsBoolean() payAdvance?: boolean;
  @ApiPropertyOptional({ type: [AttachmentDto] }) @IsOptional() @IsArray() @ArrayMaxSize(6) @ValidateNested({ each: true }) @Type(() => AttachmentDto) attachments?: AttachmentDto[];
}
class CancelDto { @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(300) reason?: string }
class ApproveEstimateDto {
  @ApiPropertyOptional({ type: [String] }) @IsOptional() @IsArray() @IsUUID('all', { each: true }) declinedItemIds?: string[];
}
class BookingPaymentDto {
  @ApiProperty({ enum: ['booking_advance', 'booking_balance'] }) @IsIn(['booking_advance', 'booking_balance']) purpose: 'booking_advance' | 'booking_balance';
}

class EstimateItemDto {
  @ApiProperty({ enum: ['service', 'labour', 'part', 'consumable', 'discount', 'other'] })
  @IsIn(['service', 'labour', 'part', 'consumable', 'discount', 'other']) kind: LineKind;
  @ApiProperty() @IsString() @MaxLength(200) description: string;
  @ApiPropertyOptional() @IsOptional() @IsUUID() serviceId?: string;
  @ApiPropertyOptional() @IsOptional() @Matches(/^[0-9]{4,8}$/) hsnSacCode?: string;
  @ApiProperty({ example: 1 }) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0.01) @Max(1000) quantity: number;
  @ApiProperty({ example: 95000, description: 'tax-exclusive, paise' }) @IsInt() @Min(-10_000_000) @Max(10_000_000) unitPricePaise: number;
  @ApiProperty({ example: 1800 }) @IsInt() @Min(0) @Max(4000) gstRateBps: number;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() isOptional?: boolean;
}
class CreateEstimateDto {
  @ApiProperty({ type: [EstimateItemDto] }) @IsArray() @ArrayMinSize(1) @ArrayMaxSize(50) @ValidateNested({ each: true }) @Type(() => EstimateItemDto) items: EstimateItemDto[];
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(1000) vendorNote?: string;
  @ApiPropertyOptional({ default: 24 }) @IsOptional() @IsInt() @Min(1) @Max(168) validForHours?: number;
}
class RejectDto { @ApiProperty() @IsString() @MaxLength(300) reason: string }
class CheckInDto { @ApiPropertyOptional() @IsOptional() @IsInt() @Min(0) odometerKm?: number }
class OfflinePaymentDto {
  @ApiProperty({ enum: ['cash', 'upi_direct'] }) @IsIn(['cash', 'upi_direct']) method: 'cash' | 'upi_direct';
  @ApiProperty() @IsInt() @Min(1) amountPaise: number;
}

@ApiTags('bookings')
@ApiBearerAuth()
@Controller('bookings')
export class BookingsController {
  constructor(private readonly bookings: BookingsService, private readonly payments: PaymentsService) {}

  @Post()
  @ApiHeader({ name: 'Idempotency-Key', required: true, description: 'UUID; a retry with the same key returns the same booking' })
  async create(@CurrentUser() user: AuthContext, @Body() dto: CreateBookingDto, @Headers('idempotency-key') key?: string) {
    if (!key || !UUID_V4ISH.test(key)) throw Errors.validation({ 'Idempotency-Key': 'header with a UUID is required' });
    const { bookingId } = await this.bookings.create(user.userId, dto, key);
    const booking = await this.bookings.view(bookingId, { customerId: user.userId });
    const payment = booking.actions.canPayAdvance ? await this.payments.createForBooking(user.userId, bookingId, 'booking_advance') : null;
    return { ...booking, payment };
  }

  @Get()
  list(@CurrentUser() user: AuthContext, @Query('status') status?: 'active' | 'past', @Query('cursor') cursor?: string) {
    return this.bookings.listForCustomer(user.userId, status, cursor);
  }

  @Get(':id')
  get(@CurrentUser() user: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.bookings.view(id, { customerId: user.userId });
  }

  @Post(':id/cancel') @HttpCode(200)
  async cancel(@CurrentUser() user: AuthContext, @Param('id', ParseUUIDPipe) id: string, @Body() dto: CancelDto) {
    await this.bookings.cancelByCustomer(user.userId, id, dto.reason);
    return this.bookings.view(id, { customerId: user.userId });
  }

  @Post(':id/estimates/:estimateId/approve') @HttpCode(200)
  async approve(@CurrentUser() user: AuthContext, @Param('id', ParseUUIDPipe) id: string,
    @Param('estimateId', ParseUUIDPipe) estimateId: string, @Body() dto: ApproveEstimateDto) {
    await this.bookings.approveEstimate(user.userId, id, estimateId, dto.declinedItemIds ?? []);
    return this.bookings.view(id, { customerId: user.userId });
  }

  @Post(':id/estimates/:estimateId/reject') @HttpCode(200)
  async rejectEstimate(@CurrentUser() user: AuthContext, @Param('id', ParseUUIDPipe) id: string,
    @Param('estimateId', ParseUUIDPipe) estimateId: string, @Body() dto: CancelDto) {
    await this.bookings.rejectEstimate(user.userId, id, estimateId, dto.reason);
    return this.bookings.view(id, { customerId: user.userId });
  }

  @Post(':id/payments')
  pay(@CurrentUser() user: AuthContext, @Param('id', ParseUUIDPipe) id: string, @Body() dto: BookingPaymentDto) {
    return this.payments.createForBooking(user.userId, id, dto.purpose);
  }
}

@ApiTags('vendor')
@ApiBearerAuth()
@ApiHeader({ name: 'X-Vendor-Id', required: true })
@Controller('vendor/bookings')
export class VendorBookingsController {
  constructor(private readonly bookings: BookingsService) {}

  @Get() @VendorRole('staff')
  list(@CurrentVendor() v: VendorContext, @Query('date') date?: string, @Query('status') status?: BookingStatus, @Query('cursor') cursor?: string) {
    if (date && !/^\d{4}-\d{2}-\d{2}$/.test(date)) throw Errors.validation({ date: 'YYYY-MM-DD' });
    return this.bookings.listForVendor(v.id, { date, status, cursor });
  }

  @Get(':id') @VendorRole('staff')
  get(@CurrentVendor() v: VendorContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.bookings.view(id, { vendorId: v.id });
  }

  @Post(':id/confirm') @HttpCode(200) @VendorRole('staff')
  confirm(@CurrentVendor() v: VendorContext, @CurrentUser() u: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.act(v, u, id, 'confirm');
  }

  @Post(':id/reject') @HttpCode(200) @VendorRole('staff')
  reject(@CurrentVendor() v: VendorContext, @CurrentUser() u: AuthContext, @Param('id', ParseUUIDPipe) id: string, @Body() dto: RejectDto) {
    return this.act(v, u, id, 'reject', { reason: dto.reason });
  }

  @Post(':id/check-in') @HttpCode(200) @VendorRole('staff')
  checkIn(@CurrentVendor() v: VendorContext, @CurrentUser() u: AuthContext, @Param('id', ParseUUIDPipe) id: string, @Body() dto: CheckInDto) {
    return this.act(v, u, id, 'check_in', { odometerKm: dto.odometerKm });
  }

  @Post(':id/start') @HttpCode(200) @VendorRole('staff')
  start(@CurrentVendor() v: VendorContext, @CurrentUser() u: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.act(v, u, id, 'start');
  }

  @Post(':id/ready') @HttpCode(200) @VendorRole('staff')
  ready(@CurrentVendor() v: VendorContext, @CurrentUser() u: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.act(v, u, id, 'ready');
  }

  @Post(':id/no-show') @HttpCode(200) @VendorRole('staff')
  noShow(@CurrentVendor() v: VendorContext, @CurrentUser() u: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.act(v, u, id, 'no_show');
  }

  @Post(':id/estimates') @VendorRole('staff')
  async estimate(@CurrentVendor() v: VendorContext, @CurrentUser() u: AuthContext, @Param('id', ParseUUIDPipe) id: string, @Body() dto: CreateEstimateDto) {
    return this.bookings.createEstimate(v.id, u.userId, id, dto.items, dto.vendorNote, dto.validForHours);
  }

  @Post(':id/offline-payment') @HttpCode(200) @VendorRole('manager')
  async offline(@CurrentVendor() v: VendorContext, @CurrentUser() u: AuthContext, @Param('id', ParseUUIDPipe) id: string, @Body() dto: OfflinePaymentDto) {
    await this.bookings.recordOfflinePayment(v.id, u.userId, id, dto.amountPaise);
    return this.bookings.view(id, { vendorId: v.id });
  }

  private async act(v: VendorContext, u: AuthContext, id: string, action: Parameters<BookingsService['vendorTransition']>[3], extra = {}) {
    await this.bookings.vendorTransition(v.id, u.userId, id, action, extra);
    return this.bookings.view(id, { vendorId: v.id });
  }
}

@Module({
  imports: [PaymentsModule],
  controllers: [BookingsController, VendorBookingsController],
  providers: [BookingsService],
  exports: [BookingsService],
})
export class BookingsModule implements OnModuleInit {
  constructor(private readonly payments: PaymentsService, private readonly bookings: BookingsService) {}
  onModuleInit() {
    this.payments.registerCaptureHandler('booking', (tx, p) => this.bookings.applyCapturedPayment(tx, p.bookingId!, p.amountPaise));
  }
}
