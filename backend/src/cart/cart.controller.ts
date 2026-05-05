// src/cart/cart.controller.ts
import { Controller, Get, Post, Body, UseGuards, Request } from '@nestjs/common';
import { ApiTags, ApiBearerAuth } from '@nestjs/swagger';
import { CartService } from './cart.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { IsString, IsInt, Min } from 'class-validator';

export class UpsertCartItemDto {
  @IsString()
  productId: string;

  @IsInt()
  @Min(0)
  quantity: number;
}

@ApiTags('cart')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('cart')
export class CartController {
  constructor(private cartService: CartService) {}

  @Get()
  getCart(@Request() req: any) {
    return this.cartService.getCart(req.user.id);
  }

  @Post()
  upsertItem(@Request() req: any, @Body() dto: UpsertCartItemDto) {
    return this.cartService.upsertItem(req.user.id, dto.productId, dto.quantity);
  }
}
