import { Body, Controller, Delete, Get, HttpCode, Module, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsBoolean, IsIn, IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';
import { AuthContext, CurrentUser } from '../../common/auth';
import { Errors } from '../../common/errors';
import { Database, InjectDb } from '../../infra/db/database';
import type { FuelType, TransmissionType } from '../../infra/db/db.types';

const FUELS = ['petrol', 'diesel', 'cng', 'lpg', 'electric', 'hybrid'];
const TRANSMISSIONS = ['manual', 'automatic', 'amt', 'cvt', 'dct'];
/** "mh 12 ab 1234" / "MH-12-AB-1234" → "MH12AB1234" */
export const normaliseReg = (v: unknown) => (typeof v === 'string' ? v.toUpperCase().replace(/[^A-Z0-9]/g, '') : v);

class CreateVehicleDto {
  @ApiProperty({ example: 1 }) @IsInt() makeId: number;
  @ApiProperty({ example: 1 }) @IsInt() modelId: number;
  @ApiPropertyOptional() @IsOptional() @IsInt() variantId?: number;
  @ApiProperty({ example: 2021 }) @IsInt() @Min(1950) @Max(2100) manufactureYear: number;
  @ApiProperty({ enum: FUELS }) @IsIn(FUELS) fuelType: FuelType;
  @ApiPropertyOptional({ enum: TRANSMISSIONS }) @IsOptional() @IsIn(TRANSMISSIONS) transmission?: TransmissionType;
  @ApiPropertyOptional({ example: 'MH 12 AB 1234' }) @IsOptional() @Transform(({ value }) => normaliseReg(value)) @IsString() @MaxLength(12)
  registrationNumber?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(40) nickname?: string;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(0) odometerKm?: number;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() isDefault?: boolean;
}

const REG_STATE = /^[A-Z]{2}[0-9]{1,2}[A-Z]{0,3}[0-9]{1,4}$/;
const REG_BH = /^[0-9]{2}BH[0-9]{4}[A-Z]{1,2}$/;

@ApiTags('me')
@ApiBearerAuth()
@Controller('me/vehicles')
export class VehiclesController {
  constructor(@InjectDb() private readonly db: Database) {}

  @Get()
  list(@CurrentUser() user: AuthContext) {
    return this.baseQuery().where('v.userId', '=', user.userId).where('v.deletedAt', 'is', null)
      .orderBy('v.isDefault', 'desc').orderBy('v.createdAt').execute();
  }

  @Post()
  async create(@CurrentUser() user: AuthContext, @Body() dto: CreateVehicleDto) {
    if (dto.registrationNumber && !REG_STATE.test(dto.registrationNumber) && !REG_BH.test(dto.registrationNumber)) {
      throw Errors.validation({ registrationNumber: 'not a valid Indian registration number' });
    }
    const model = await this.db.selectFrom('vehicleModels').select(['id', 'makeId']).where('id', '=', dto.modelId).executeTakeFirst();
    if (!model || model.makeId !== dto.makeId) throw Errors.validation({ modelId: 'model does not belong to this make' });
    if (dto.variantId) {
      const variant = await this.db.selectFrom('vehicleVariants').select('modelId').where('id', '=', dto.variantId).executeTakeFirst();
      if (!variant || variant.modelId !== dto.modelId) throw Errors.validation({ variantId: 'variant does not belong to this model' });
    }
    const id = await this.db.transaction().execute(async (tx) => {
      const existing = await tx.selectFrom('vehicles').select('id').where('userId', '=', user.userId).where('deletedAt', 'is', null).execute();
      const isDefault = dto.isDefault ?? existing.length === 0;
      if (isDefault) await tx.updateTable('vehicles').set({ isDefault: false }).where('userId', '=', user.userId).execute();
      const row = await tx.insertInto('vehicles').values({
        userId: user.userId, makeId: dto.makeId, modelId: dto.modelId, variantId: dto.variantId ?? null,
        manufactureYear: dto.manufactureYear, fuelType: dto.fuelType, transmission: dto.transmission ?? null,
        registrationNumber: dto.registrationNumber || null, nickname: dto.nickname ?? null,
        odometerKm: dto.odometerKm ?? null, isDefault,
      }).returning('id').executeTakeFirstOrThrow();
      return row.id;
    });
    return this.baseQuery().where('v.id', '=', id).executeTakeFirstOrThrow();
  }

  @Delete(':id') @HttpCode(204)
  async remove(@CurrentUser() user: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    const r = await this.db.updateTable('vehicles').set({ deletedAt: new Date(), isDefault: false })
      .where('id', '=', id).where('userId', '=', user.userId).where('deletedAt', 'is', null).executeTakeFirst();
    if (!r.numUpdatedRows) throw Errors.notFound('Vehicle');
  }

  private baseQuery() {
    return this.db.selectFrom('vehicles as v')
      .innerJoin('vehicleMakes as mk', 'mk.id', 'v.makeId')
      .innerJoin('vehicleModels as md', 'md.id', 'v.modelId')
      .leftJoin('vehicleVariants as vr', 'vr.id', 'v.variantId')
      .select([
        'v.id', 'v.makeId', 'mk.name as makeName', 'v.modelId', 'md.name as modelName', 'md.bodyType',
        'v.variantId', 'vr.name as variantName', 'v.manufactureYear', 'v.fuelType', 'v.transmission',
        'v.registrationNumber', 'v.nickname', 'v.odometerKm', 'v.isDefault',
      ]);
  }
}

@Module({ controllers: [VehiclesController] })
export class VehiclesModule {}
