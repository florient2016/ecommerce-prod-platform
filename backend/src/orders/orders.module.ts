import { Module } from '@nestjs/common';
import { OrdersService } from './orders.service';
import { OrdersController, AdminOrdersController } from './orders.controller';
import { CartModule } from '../cart/cart.module';

@Module({
  imports: [CartModule],
  providers: [OrdersService],
  controllers: [OrdersController, AdminOrdersController],
})
export class OrdersModule {}
