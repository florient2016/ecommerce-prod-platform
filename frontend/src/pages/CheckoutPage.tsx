// src/pages/CheckoutPage.tsx
import { useForm } from 'react-hook-form';
import { useNavigate } from 'react-router-dom';
import { ordersApi } from '../lib/api';
import { useCartStore } from '../store/cart.store';
import { useState } from 'react';
import { Loader2, CheckCircle } from 'lucide-react';

export default function CheckoutPage() {
  const { register, handleSubmit } = useForm();
  const { items, total, fetchCart } = useCartStore();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(false);
  const [success, setSuccess] = useState(false);
  const [error, setError] = useState('');

  const onSubmit = async (data: any) => {
    try {
      setLoading(true);
      setError('');
      await ordersApi.create({ shippingAddress: data });
      await fetchCart();
      setSuccess(true);
      setTimeout(() => navigate('/orders'), 3000);
    } catch (e: any) {
      setError(e.response?.data?.message || 'Erreur lors de la commande');
    } finally { setLoading(false); }
  };

  if (success) return (
    <div className="max-w-md mx-auto text-center py-20">
      <CheckCircle className="h-16 w-16 text-green-500 mx-auto mb-4" />
      <h2 className="text-2xl font-bold text-gray-900 mb-2">Commande confirmée !</h2>
      <p className="text-gray-500">Redirection vers vos commandes...</p>
    </div>
  );

  return (
    <div className="max-w-3xl mx-auto grid grid-cols-1 md:grid-cols-2 gap-8">
      <div>
        <h1 className="text-2xl font-bold text-gray-900 mb-6">Adresse de livraison</h1>
        {error && <div className="bg-red-50 text-red-700 p-3 rounded-lg mb-4 text-sm">{error}</div>}
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          {[
            { name: 'street', label: 'Adresse', placeholder: '12 rue de la Paix' },
            { name: 'city', label: 'Ville', placeholder: 'Paris' },
            { name: 'postalCode', label: 'Code postal', placeholder: '75001' },
            { name: 'country', label: 'Pays', placeholder: 'France' },
          ].map(f => (
            <div key={f.name}>
              <label className="block text-sm font-medium text-gray-700 mb-1">{f.label}</label>
              <input {...register(f.name, { required: true })} placeholder={f.placeholder}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 focus:ring-2 focus:ring-blue-500 focus:border-transparent" />
            </div>
          ))}
          <div className="bg-gray-50 rounded-lg p-4 text-sm text-gray-600">
            <p className="font-medium mb-1">💳 Paiement simulé</p>
            <p>Le paiement est automatiquement validé en mode démo.</p>
          </div>
          <button type="submit" disabled={loading}
            className="w-full bg-blue-600 text-white py-3 rounded-lg font-semibold hover:bg-blue-700 flex items-center justify-center gap-2 disabled:opacity-70">
            {loading && <Loader2 className="h-5 w-5 animate-spin" />}
            Confirmer la commande — {total} €
          </button>
        </form>
      </div>
      <div>
        <h2 className="text-lg font-bold text-gray-900 mb-4">Récapitulatif</h2>
        <div className="bg-white rounded-xl border border-gray-100 p-4 space-y-3">
          {items.map((item: any) => (
            <div key={item.id} className="flex justify-between text-sm">
              <span>{item.product.name} × {item.quantity}</span>
              <span className="font-medium">{(Number(item.product.price) * item.quantity).toFixed(2)} €</span>
            </div>
          ))}
          <div className="border-t pt-3 flex justify-between font-bold">
            <span>Total</span>
            <span>{total} €</span>
          </div>
        </div>
      </div>
    </div>
  );
}
