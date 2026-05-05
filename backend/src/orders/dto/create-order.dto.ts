// src/orders/dto/create-order.dto.ts
import { IsObject, IsString, IsOptional } from 'class-validator';

export class ShippingAddressDto {
  @IsString() street: string;
  @IsString() city: string;
  @IsString() postalCode: string;
  @IsString() country: string;
  @IsOptional() @IsString() state?: string;
}

export class CreateOrderDto {
  @IsObject()
  shippingAddress: ShippingAddressDto;
}
