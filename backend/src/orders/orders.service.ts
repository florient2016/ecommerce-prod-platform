// src/orders/orders.service.ts
import { Injectable, BadRequestException, NotFoundException, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CartService } from '../cart/cart.service';
import { CreateOrderDto } from './dto/create-order.dto';
import { v4 as uuidv4 } from 'uuid';

@Injectable()
export class OrdersService {
  private readonly logger = new Logger(OrdersService.name);

  constructor(
    private prisma: PrismaService,
    private cartService: CartService,
  ) {}

  async createOrder(userId: string, dto: CreateOrderDto) {
    const cart = await this.cartService.getCart(userId);
    if (!cart.items || cart.items.length === 0) {
      throw new BadRequestException('Cart is empty');
    }

    // Mock payment processing
    const paymentRef = `PAY-${uuidv4().toUpperCase().slice(0, 8)}`;
    const paymentSuccess = true; // Mock: always succeeds

    const totalAmount = cart.items.reduce(
      (sum: number, item: any) => sum + Number(item.product.price) * item.quantity,
      0,
    );

    // Create order in transaction
    const order = await this.prisma.$transaction(async (tx) => {
      // Check stock for all items
      for (const item of cart.items as any[]) {
        const product = await tx.product.findUnique({ where: { id: item.productId } });
        if (!product || product.stock < item.quantity) {
          throw new BadRequestException(`Insufficient stock for ${item.product.name}`);
        }
      }

      // Create order
      const newOrder = await tx.order.create({
        data: {
          userId,
          totalAmount,
          shippingAddress: dto.shippingAddress,
          paymentStatus: paymentSuccess ? 'PAID' : 'FAILED',
          paymentRef,
          status: paymentSuccess ? 'CONFIRMED' : 'PENDING',
          items: {
            create: (cart.items as any[]).map((item) => ({
              productId: item.productId,
              quantity: item.quantity,
              unitPrice: item.product.price,
              total: Number(item.product.price) * item.quantity,
            })),
          },
        },
        include: { items: { include: { product: true } } },
      });

      // Decrement stock
      for (const item of cart.items as any[]) {
        await tx.product.update({
          where: { id: item.productId },
          data: { stock: { decrement: item.quantity } },
        });
      }

      return newOrder;
    });

    // Clear cart
    await this.cartService.clearCart(userId);
    this.logger.log(`Order created: ${order.id} for user ${userId}, total: ${totalAmount}`);

    return order;
  }

  async getMyOrders(userId: string) {
    return this.prisma.order.findMany({
      where: { userId },
      include: { items: { include: { product: { select: { id: true, name: true, imageUrl: true } } } } },
      orderBy: { createdAt: 'desc' },
    });
  }

  async getAllOrders(page = 1, limit = 20) {
    const skip = (page - 1) * limit;
    const [orders, total] = await Promise.all([
      this.prisma.order.findMany({
        include: {
          user: { select: { id: true, email: true, firstName: true, lastName: true } },
          items: { include: { product: { select: { id: true, name: true } } } },
        },
        skip,
        take: limit,
        orderBy: { createdAt: 'desc' },
      }),
      this.prisma.order.count(),
    ]);
    return { data: orders, total, page, limit };
  }

  async updateOrderStatus(id: string, status: string) {
    const order = await this.prisma.order.findUnique({ where: { id } });
    if (!order) throw new NotFoundException('Order not found');
    return this.prisma.order.update({ where: { id }, data: { status: status as any } });
  }
}
