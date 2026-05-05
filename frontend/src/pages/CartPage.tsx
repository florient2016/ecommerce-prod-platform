// src/pages/CartPage.tsx
import { useCartStore } from '../store/cart.store';
import { Link, useNavigate } from 'react-router-dom';
import { Trash2, Plus, Minus, ShoppingBag } from 'lucide-react';

export default function CartPage() {
  const { items, total, upsertItem } = useCartStore();
  const navigate = useNavigate();

  if (items.length === 0) {
    return (
      <div className="text-center py-20">
        <ShoppingBag className="h-16 w-16 text-gray-200 mx-auto mb-4" />
        <h2 className="text-xl font-semibold text-gray-500 mb-4">Votre panier est vide</h2>
        <Link to="/products" className="bg-blue-600 text-white px-6 py-3 rounded-lg hover:bg-blue-700">
          Découvrir nos produits
        </Link>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
      <div className="lg:col-span-2 space-y-4">
        <h1 className="text-2xl font-bold text-gray-900 mb-6">Mon panier</h1>
        {items.map((item: any) => (
          <div key={item.id} className="bg-white rounded-xl border border-gray-100 p-4 flex gap-4">
            <div className="w-20 h-20 bg-gray-100 rounded-lg overflow-hidden flex-shrink-0">
              {item.product.imageUrl && (
                <img src={item.product.imageUrl} alt={item.product.name} className="w-full h-full object-cover" />
              )}
            </div>
            <div className="flex-1">
              <h3 className="font-semibold text-gray-900">{item.product.name}</h3>
              <p className="text-blue-600 font-bold">{Number(item.product.price).toFixed(2)} €</p>
              <div className="flex items-center gap-2 mt-2">
                <button onClick={() => upsertItem(item.productId, item.quantity - 1)}
                  className="p-1 rounded border hover:bg-gray-50">
                  <Minus className="h-4 w-4" />
                </button>
                <span className="w-8 text-center font-medium">{item.quantity}</span>
                <button onClick={() => upsertItem(item.productId, item.quantity + 1)}
                  className="p-1 rounded border hover:bg-gray-50">
                  <Plus className="h-4 w-4" />
                </button>
                <button onClick={() => upsertItem(item.productId, 0)}
                  className="ml-auto p-1 text-red-400 hover:text-red-600">
                  <Trash2 className="h-4 w-4" />
                </button>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Summary */}
      <div className="lg:col-span-1">
        <div className="bg-white rounded-xl border border-gray-100 p-6 sticky top-24">
          <h2 className="text-lg font-bold text-gray-900 mb-4">Récapitulatif</h2>
          <div className="flex justify-between text-gray-600 mb-2">
            <span>Sous-total</span>
            <span>{total} €</span>
          </div>
          <div className="flex justify-between text-gray-600 mb-4">
            <span>Livraison</span>
            <span className="text-green-600">Gratuite</span>
          </div>
          <div className="border-t pt-4 flex justify-between font-bold text-lg">
            <span>Total</span>
            <span>{total} €</span>
          </div>
          <button onClick={() => navigate('/checkout')}
            className="w-full mt-6 bg-blue-600 text-white py-3 rounded-lg font-semibold hover:bg-blue-700">
            Commander
          </button>
        </div>
      </div>
    </div>
  );
}
