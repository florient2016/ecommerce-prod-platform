// src/pages/HomePage.tsx
import { Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { productsApi } from '../lib/api';
import ProductCard from '../components/ProductCard';
import { ArrowRight, Shield, Truck, CreditCard } from 'lucide-react';

export default function HomePage() {
  const { data } = useQuery({
    queryKey: ['products', 'featured'],
    queryFn: () => productsApi.list({ limit: 8 }),
  });

  const products = data?.data?.data || [];

  return (
    <div className="space-y-16">
      {/* Hero */}
      <section className="bg-gradient-to-br from-blue-600 to-blue-800 rounded-2xl p-12 text-white text-center">
        <h1 className="text-4xl md:text-5xl font-bold mb-4">
          Bienvenue sur ITSSolutions Shop
        </h1>
        <p className="text-xl text-blue-100 mb-8 max-w-2xl mx-auto">
          Découvrez notre sélection de produits premium. Livraison rapide, paiement sécurisé.
        </p>
        <Link to="/products"
          className="inline-flex items-center gap-2 bg-white text-blue-600 px-8 py-3 rounded-lg font-semibold hover:bg-blue-50 transition-colors">
          Voir tous les produits <ArrowRight className="h-5 w-5" />
        </Link>
      </section>

      {/* Features */}
      <section className="grid grid-cols-1 md:grid-cols-3 gap-8">
        {[
          { icon: <Truck className="h-8 w-8 text-blue-600" />, title: 'Livraison rapide', desc: 'Expédition sous 24h ouvrées' },
          { icon: <Shield className="h-8 w-8 text-green-600" />, title: 'Paiement sécurisé', desc: 'Transactions 100% sécurisées' },
          { icon: <CreditCard className="h-8 w-8 text-purple-600" />, title: 'Retours gratuits', desc: '30 jours pour changer d\'avis' },
        ].map((f, i) => (
          <div key={i} className="bg-white p-6 rounded-xl shadow-sm border border-gray-100 text-center">
            <div className="flex justify-center mb-4">{f.icon}</div>
            <h3 className="font-semibold text-gray-900 mb-2">{f.title}</h3>
            <p className="text-gray-500 text-sm">{f.desc}</p>
          </div>
        ))}
      </section>

      {/* Featured products */}
      <section>
        <div className="flex justify-between items-center mb-6">
          <h2 className="text-2xl font-bold text-gray-900">Produits populaires</h2>
          <Link to="/products" className="text-blue-600 hover:text-blue-800 flex items-center gap-1 font-medium">
            Voir tout <ArrowRight className="h-4 w-4" />
          </Link>
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
          {products.map((p: any) => <ProductCard key={p.id} product={p} />)}
        </div>
      </section>
    </div>
  );
}
