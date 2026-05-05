// src/products/dto/create-product.dto.ts
import { IsString, IsNumber, IsInt, IsOptional, IsUrl, MinLength, Min } from 'class-validator';

export class CreateProductDto {
  @IsString()
  @MinLength(2)
  name: string;

  @IsString()
  @MinLength(10)
  description: string;

  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  price: number;

  @IsInt()
  @Min(0)
  stock: number;

  @IsString()
  categoryId: string;

  @IsOptional()
  @IsUrl()
  imageUrl?: string;
}
