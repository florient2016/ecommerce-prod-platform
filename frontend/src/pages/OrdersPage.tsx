// src/pages/OrdersPage.tsx
import { useQuery } from '@tanstack/react-query';
import { ordersApi } from '../lib/api';
import { Loader2, Package } from 'lucide-react';

const STATUS_COLORS: Record<string, string> = {
  PENDING: 'bg-yellow-50 text-yellow-700',
  CONFIRMED: 'bg-blue-50 text-blue-700',
  PROCESSING: 'bg-purple-50 text-purple-700',
  SHIPPED: 'bg-indigo-50 text-indigo-700',
  DELIVERED: 'bg-green-50 text-green-700',
  CANCELLED: 'bg-red-50 text-red-700',
};

export default function OrdersPage() {
  const { data, isLoading } = useQuery({ queryKey: ['my-orders'], queryFn: () => ordersApi.list() });
  const orders = data?.data || [];

  if (isLoading) return <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-blue-600" /></div>;

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      <h1 className="text-2xl font-bold text-gray-900">Mes commandes</h1>
      {orders.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <Package className="h-12 w-12 mx-auto mb-3 text-gray-200" />
          <p>Aucune commande pour le moment</p>
        </div>
      ) : orders.map((order: any) => (
        <div key={order.id} className="bg-white rounded-xl border border-gray-100 p-6">
          <div className="flex justify-between items-start mb-4">
            <div>
              <p className="text-xs text-gray-400 font-mono">{order.id}</p>
              <p className="text-sm text-gray-500 mt-1">{new Date(order.createdAt).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' })}</p>
            </div>
            <div className="text-right">
              <span className={`inline-block px-3 py-1 rounded-full text-xs font-medium ${STATUS_COLORS[order.status] || 'bg-gray-50 text-gray-700'}`}>
                {order.status}
              </span>
              <p className="font-bold text-lg mt-1">{Number(order.totalAmount).toFixed(2)} €</p>
            </div>
          </div>
          <div className="space-y-2">
            {order.items.map((item: any) => (
              <div key={item.id} className="flex justify-between text-sm text-gray-600">
                <span>{item.product?.name} × {item.quantity}</span>
                <span>{Number(item.total).toFixed(2)} €</span>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}
