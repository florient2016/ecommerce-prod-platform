// src/pages/admin/AdminDashboard.tsx
import { useQuery } from '@tanstack/react-query';
import { ordersApi, productsApi, usersApi } from '../../lib/api';
import { Link } from 'react-router-dom';
import { ShoppingBag, Package, Users, TrendingUp } from 'lucide-react';

export default function AdminDashboard() {
  const { data: ordersData } = useQuery({ queryKey: ['admin-orders'], queryFn: () => ordersApi.adminList({ limit: 5 }) });
  const { data: productsData } = useQuery({ queryKey: ['products-count'], queryFn: () => productsApi.list({ limit: 1 }) });
  const { data: usersData } = useQuery({ queryKey: ['users-count'], queryFn: () => usersApi.list({ limit: 1 }) });

  const stats = [
    { label: 'Commandes', value: ordersData?.data?.total || 0, icon: <ShoppingBag className="h-6 w-6" />, color: 'text-blue-600 bg-blue-50', link: '/admin/orders' },
    { label: 'Produits', value: productsData?.data?.total || 0, icon: <Package className="h-6 w-6" />, color: 'text-green-600 bg-green-50', link: '/admin/products' },
    { label: 'Utilisateurs', value: usersData?.data?.total || 0, icon: <Users className="h-6 w-6" />, color: 'text-purple-600 bg-purple-50', link: '#' },
  ];

  const recentOrders = ordersData?.data?.data || [];

  return (
    <div className="space-y-8">
      <div className="flex items-center gap-3">
        <TrendingUp className="h-7 w-7 text-purple-600" />
        <h1 className="text-2xl font-bold text-gray-900">Dashboard Admin</h1>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-6">
        {stats.map((s, i) => (
          <Link key={i} to={s.link} className="bg-white rounded-xl border border-gray-100 p-6 hover:shadow-md transition-shadow">
            <div className={`inline-flex p-3 rounded-lg ${s.color} mb-4`}>{s.icon}</div>
            <p className="text-3xl font-bold text-gray-900">{s.value}</p>
            <p className="text-gray-500 mt-1">{s.label}</p>
          </Link>
        ))}
      </div>

      {/* Quick links */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <Link to="/admin/products" className="flex items-center gap-3 bg-white p-4 rounded-xl border border-gray-100 hover:bg-gray-50">
          <Package className="h-5 w-5 text-green-600" />
          <span className="font-medium">Gérer les produits</span>
        </Link>
        <Link to="/admin/orders" className="flex items-center gap-3 bg-white p-4 rounded-xl border border-gray-100 hover:bg-gray-50">
          <ShoppingBag className="h-5 w-5 text-blue-600" />
          <span className="font-medium">Gérer les commandes</span>
        </Link>
      </div>

      {/* Recent orders */}
      <div className="bg-white rounded-xl border border-gray-100 p-6">
        <h2 className="text-lg font-bold text-gray-900 mb-4">Dernières commandes</h2>
        {recentOrders.length === 0 ? (
          <p className="text-gray-400 text-sm">Aucune commande</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-gray-400 border-b">
                  <th className="pb-3 font-medium">ID</th>
                  <th className="pb-3 font-medium">Client</th>
                  <th className="pb-3 font-medium">Montant</th>
                  <th className="pb-3 font-medium">Statut</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {recentOrders.map((o: any) => (
                  <tr key={o.id} className="hover:bg-gray-50">
                    <td className="py-3 font-mono text-xs text-gray-400">{o.id.slice(0, 8)}...</td>
                    <td className="py-3">{o.user?.firstName} {o.user?.lastName}</td>
                    <td className="py-3 font-medium">{Number(o.totalAmount).toFixed(2)} €</td>
                    <td className="py-3">
                      <span className="px-2 py-0.5 bg-blue-50 text-blue-700 rounded text-xs">{o.status}</span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
