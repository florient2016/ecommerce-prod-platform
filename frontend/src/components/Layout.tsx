// src/components/Layout.tsx
import { Outlet, Link, useNavigate } from 'react-router-dom';
import { ShoppingCart, User, LogOut, LayoutDashboard, Package } from 'lucide-react';
import { useAuthStore } from '../store/auth.store';
import { useCartStore } from '../store/cart.store';
import { useEffect } from 'react';

export default function Layout() {
  const { isAuthenticated, isAdmin, user, logout } = useAuthStore();
  const { fetchCart, itemCount } = useCartStore();
  const navigate = useNavigate();

  useEffect(() => {
    if (isAuthenticated) fetchCart();
  }, [isAuthenticated]);

  const handleLogout = () => {
    logout();
    navigate('/');
  };

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Navbar */}
      <nav className="bg-white shadow-sm border-b border-gray-200 sticky top-0 z-40">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center h-16">
            {/* Logo */}
            <Link to="/" className="flex items-center space-x-2">
              <Package className="h-6 w-6 text-blue-600" />
              <span className="font-bold text-lg text-gray-900">ITSSolutions Shop</span>
            </Link>

            {/* Nav links */}
            <div className="hidden md:flex items-center space-x-6">
              <Link to="/products" className="text-gray-600 hover:text-blue-600 font-medium transition-colors">
                Produits
              </Link>
              {isAdmin && (
                <Link to="/admin" className="text-purple-600 hover:text-purple-800 font-medium flex items-center gap-1">
                  <LayoutDashboard className="h-4 w-4" />Admin
                </Link>
              )}
            </div>

            {/* Right side */}
            <div className="flex items-center space-x-4">
              {isAuthenticated && (
                <Link to="/cart" className="relative p-2 text-gray-600 hover:text-blue-600">
                  <ShoppingCart className="h-6 w-6" />
                  {itemCount() > 0 && (
                    <span className="absolute -top-1 -right-1 bg-blue-600 text-white text-xs rounded-full h-5 w-5 flex items-center justify-center">
                      {itemCount()}
                    </span>
                  )}
                </Link>
              )}

              {isAuthenticated ? (
                <div className="flex items-center space-x-2">
                  <Link to="/account" className="flex items-center gap-1 text-gray-600 hover:text-blue-600">
                    <User className="h-5 w-5" />
                    <span className="hidden md:inline text-sm">{user?.firstName}</span>
                  </Link>
                  <button onClick={handleLogout} className="p-2 text-gray-400 hover:text-red-500">
                    <LogOut className="h-5 w-5" />
                  </button>
                </div>
              ) : (
                <div className="flex items-center space-x-2">
                  <Link to="/login" className="text-gray-600 hover:text-blue-600 font-medium">Connexion</Link>
                  <Link to="/register" className="bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700 font-medium text-sm">
                    S'inscrire
                  </Link>
                </div>
              )}
            </div>
          </div>
        </div>
      </nav>

      {/* Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <Outlet />
      </main>

      {/* Footer */}
      <footer className="bg-white border-t border-gray-200 mt-16">
        <div className="max-w-7xl mx-auto px-4 py-8 text-center text-gray-500 text-sm">
          © 2024 ITSSolutions Shop. Tous droits réservés.
        </div>
      </footer>
    </div>
  );
}
