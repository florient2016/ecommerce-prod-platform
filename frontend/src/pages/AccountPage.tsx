// src/pages/AccountPage.tsx
import { useQuery } from '@tanstack/react-query';
import { usersApi } from '../lib/api';
import { useAuthStore } from '../store/auth.store';
import { Link } from 'react-router-dom';
import { User, ShoppingBag, Shield } from 'lucide-react';

export default function AccountPage() {
  const { user, isAdmin } = useAuthStore();
  const { data } = useQuery({ queryKey: ['me'], queryFn: () => usersApi.me() });
  const profile = data?.data || user;

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <h1 className="text-2xl font-bold text-gray-900">Mon compte</h1>
      <div className="bg-white rounded-xl border border-gray-100 p-6">
        <div className="flex items-center gap-4 mb-6">
          <div className="h-16 w-16 bg-blue-100 rounded-full flex items-center justify-center">
            <User className="h-8 w-8 text-blue-600" />
          </div>
          <div>
            <h2 className="text-xl font-semibold text-gray-900">{profile?.firstName} {profile?.lastName}</h2>
            <p className="text-gray-500">{profile?.email}</p>
            <span className={`inline-block mt-1 px-2 py-0.5 rounded text-xs font-medium ${isAdmin ? 'bg-purple-50 text-purple-700' : 'bg-blue-50 text-blue-700'}`}>
              {profile?.role}
            </span>
          </div>
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Link to="/orders" className="flex items-center gap-3 p-4 border border-gray-100 rounded-lg hover:bg-gray-50 transition-colors">
            <ShoppingBag className="h-5 w-5 text-blue-600" />
            <div>
              <p className="font-medium text-gray-900">Mes commandes</p>
              <p className="text-sm text-gray-500">Historique et suivi</p>
            </div>
          </Link>
          {isAdmin && (
            <Link to="/admin" className="flex items-center gap-3 p-4 border border-purple-100 rounded-lg hover:bg-purple-50 transition-colors">
              <Shield className="h-5 w-5 text-purple-600" />
              <div>
                <p className="font-medium text-gray-900">Administration</p>
                <p className="text-sm text-gray-500">Dashboard admin</p>
              </div>
            </Link>
          )}
        </div>
      </div>
    </div>
  );
}
