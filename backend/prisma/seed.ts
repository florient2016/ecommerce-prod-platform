// prisma/seed.ts
import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcrypt';

const prisma = new PrismaClient();

async function main() {
  console.log('🌱 Seeding database...');

  // Admin user
  const adminHash = await bcrypt.hash('Admin@2024!Secure', 12);
  await prisma.user.upsert({
    where: { email: 'admin@itssolutions.it' },
    update: {},
    create: {
      email: 'admin@itssolutions.it',
      passwordHash: adminHash,
      firstName: 'Admin',
      lastName: 'System',
      role: 'ADMIN',
    },
  });

  // Demo customer
  const customerHash = await bcrypt.hash('Customer@2024!', 12);
  await prisma.user.upsert({
    where: { email: 'customer@example.com' },
    update: {},
    create: {
      email: 'customer@example.com',
      passwordHash: customerHash,
      firstName: 'John',
      lastName: 'Doe',
      role: 'CUSTOMER',
    },
  });

  // Categories
  const categories = [
    { name: 'Électronique', slug: 'electronique', description: 'Appareils et gadgets électroniques' },
    { name: 'Vêtements', slug: 'vetements', description: 'Mode et accessoires' },
    { name: 'Maison & Jardin', slug: 'maison-jardin', description: 'Décoration et mobilier' },
    { name: 'Sport', slug: 'sport', description: 'Équipements sportifs' },
  ];

  const createdCategories: Record<string, string> = {};
  for (const cat of categories) {
    const c = await prisma.category.upsert({
      where: { slug: cat.slug },
      update: {},
      create: cat,
    });
    createdCategories[cat.slug] = c.id;
  }

  // Products
  const products = [
    {
      name: 'Smartphone Pro X',
      slug: 'smartphone-pro-x',
      description: 'Smartphone haut de gamme avec écran AMOLED 6.7", 256Go, 5G',
      price: 899.99,
      stock: 50,
      categoryId: createdCategories['electronique'],
      imageUrl: 'https://images.unsplash.com/photo-1511707171634-5f897ff02aa9?w=400',
    },
    {
      name: 'Laptop UltraBook 15',
      slug: 'laptop-ultrabook-15',
      description: 'Ordinateur portable ultra-fin, Intel i7, 16Go RAM, 512Go SSD',
      price: 1299.99,
      stock: 30,
      categoryId: createdCategories['electronique'],
      imageUrl: 'https://images.unsplash.com/photo-1496181133206-80ce9b88a853?w=400',
    },
    {
      name: 'Casque Audio Premium',
      slug: 'casque-audio-premium',
      description: 'Casque sans fil avec réduction de bruit active, 30h autonomie',
      price: 299.99,
      stock: 100,
      categoryId: createdCategories['electronique'],
      imageUrl: 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=400',
    },
    {
      name: 'T-Shirt Premium Coton',
      slug: 'tshirt-premium-coton',
      description: 'T-shirt 100% coton biologique, coupe moderne',
      price: 29.99,
      stock: 200,
      categoryId: createdCategories['vetements'],
      imageUrl: 'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?w=400',
    },
    {
      name: 'Veste Imperméable',
      slug: 'veste-impermeable',
      description: 'Veste de randonnée imperméable, légère et respirante',
      price: 149.99,
      stock: 75,
      categoryId: createdCategories['vetements'],
      imageUrl: 'https://images.unsplash.com/photo-1544966503-7cc5ac882d55?w=400',
    },
    {
      name: 'Canapé Design 3 Places',
      slug: 'canape-design-3-places',
      description: 'Canapé scandinave en tissu premium, pieds chêne',
      price: 799.99,
      stock: 15,
      categoryId: createdCategories['maison-jardin'],
      imageUrl: 'https://images.unsplash.com/photo-1555041469-a586c61ea9bc?w=400',
    },
    {
      name: 'Vélo de Route Carbon',
      slug: 'velo-route-carbon',
      description: 'Vélo de route en carbone, groupe Shimano 105, 22 vitesses',
      price: 1899.99,
      stock: 10,
      categoryId: createdCategories['sport'],
      imageUrl: 'https://images.unsplash.com/photo-1485965120184-e220f721d03e?w=400',
    },
    {
      name: 'Tapis de Yoga',
      slug: 'tapis-yoga',
      description: 'Tapis de yoga antidérapant, 6mm, matériau éco-responsable',
      price: 49.99,
      stock: 150,
      categoryId: createdCategories['sport'],
      imageUrl: 'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?w=400',
    },
  ];

  for (const product of products) {
    await prisma.product.upsert({
      where: { slug: product.slug },
      update: {},
      create: {
        ...product,
        price: product.price,
      },
    });
  }

  console.log('✅ Seeding terminé');
  console.log('Admin: admin@itssolutions.it / Admin@2024!Secure');
  console.log('Customer: customer@example.com / Customer@2024!');
}

main()
  .catch(console.error)
  .finally(() => prisma.$disconnect());
