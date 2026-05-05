// src/pages/ProductDetailPage.tsx
import { useParams, useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { productsApi } from '../lib/api';
import { useCartStore } from '../store/cart.store';
import { useAuthStore } from '../store/auth.store';
import { ShoppingCart, Loader2, ArrowLeft, Package } from 'lucide-react';
import { useState } from 'react';

export default function ProductDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { upsertItem } = useCartStore();
  const { isAuthenticated } = useAuthStore();
  const [qty, setQty] = useState(1);
  const [adding, setAdding] = useState(false);

  const { data, isLoading, isError } = useQuery({
    queryKey: ['product', id],
    queryFn: () => productsApi.get(id!),
  });

  const product = data?.data;

  const handleAdd = async () => {
    if (!isAuthenticated) { navigate('/login'); return; }
    setAdding(true);
    await upsertItem(product.id, qty);
    setAdding(false);
    navigate('/cart');
  };

  if (isLoading) return <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-blue-600" /></div>;
  if (isError || !product) return <div className="text-center py-20 text-gray-400">Produit non trouvé</div>;

  return (
    <div className="max-w-5xl mx-auto">
      <button onClick={() => navigate(-1)} className="flex items-center gap-2 text-gray-500 hover:text-gray-700 mb-6">
        <ArrowLeft className="h-4 w-4" /> Retour
      </button>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-10">
        <div className="aspect-square bg-gray-100 rounded-2xl overflow-hidden">
          {product.imageUrl
            ? <img src={product.imageUrl} alt={product.name} className="w-full h-full object-cover" />
            : <div className="w-full h-full flex items-center justify-center"><Package className="h-24 w-24 text-gray-300" /></div>
          }
        </div>
        <div className="space-y-6">
          {product.category && <span className="text-sm font-medium text-blue-600 uppercase tracking-wide">{product.category.name}</span>}
          <h1 className="text-3xl font-bold text-gray-900">{product.name}</h1>
          <p className="text-4xl font-bold text-gray-900">{Number(product.price).toFixed(2)} €</p>
          <p className="text-gray-600 leading-relaxed">{product.description}</p>
          <div className="flex items-center gap-2">
            <span className={`inline-flex items-center px-3 py-1 rounded-full text-sm font-medium ${product.stock > 0 ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-700'}`}>
              {product.stock > 0 ? `En stock (${product.stock})` : 'Rupture de stock'}
            </span>
          </div>
          {product.stock > 0 && (
            <div className="flex items-center gap-4">
              <div className="flex items-center border border-gray-300 rounded-lg overflow-hidden">
                <button onClick={() => setQty(q => Math.max(1, q - 1))} className="px-3 py-2 hover:bg-gray-50">-</button>
                <span className="px-4 py-2 font-medium">{qty}</span>
                <button onClick={() => setQty(q => Math.min(product.stock, q + 1))} className="px-3 py-2 hover:bg-gray-50">+</button>
              </div>
              <button onClick={handleAdd} disabled={adding}
                className="flex-1 flex items-center justify-center gap-2 bg-blue-600 text-white py-3 rounded-lg font-semibold hover:bg-blue-700 disabled:opacity-70">
                {adding ? <Loader2 className="h-5 w-5 animate-spin" /> : <ShoppingCart className="h-5 w-5" />}
                Ajouter au panier
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
