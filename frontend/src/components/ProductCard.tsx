// src/components/ProductCard.tsx
import { Link } from 'react-router-dom';
import { ShoppingCart } from 'lucide-react';
import { useCartStore } from '../store/cart.store';
import { useAuthStore } from '../store/auth.store';
import { useNavigate } from 'react-router-dom';

interface ProductCardProps {
  product: {
    id: string;
    name: string;
    price: number;
    imageUrl?: string;
    category?: { name: string };
    stock: number;
  };
}

export default function ProductCard({ product }: ProductCardProps) {
  const { upsertItem } = useCartStore();
  const { isAuthenticated } = useAuthStore();
  const navigate = useNavigate();

  const handleAddToCart = async (e: React.MouseEvent) => {
    e.preventDefault();
    if (!isAuthenticated) { navigate('/login'); return; }
    await upsertItem(product.id, 1);
  };

  return (
    <Link to={`/products/${product.id}`} className="group">
      <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden hover:shadow-md transition-shadow">
        <div className="aspect-square bg-gray-100 overflow-hidden">
          {product.imageUrl ? (
            <img src={product.imageUrl} alt={product.name}
              className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300" />
          ) : (
            <div className="w-full h-full flex items-center justify-center text-gray-300 text-4xl">📦</div>
          )}
        </div>
        <div className="p-4">
          {product.category && (
            <span className="text-xs text-blue-600 font-medium uppercase tracking-wide">
              {product.category.name}
            </span>
          )}
          <h3 className="font-semibold text-gray-900 mt-1 line-clamp-2">{product.name}</h3>
          <div className="flex items-center justify-between mt-3">
            <span className="text-xl font-bold text-gray-900">
              {Number(product.price).toFixed(2)} €
            </span>
            {product.stock > 0 ? (
              <button onClick={handleAddToCart}
                className="flex items-center gap-1 bg-blue-600 text-white px-3 py-2 rounded-lg hover:bg-blue-700 text-sm font-medium transition-colors">
                <ShoppingCart className="h-4 w-4" />
                Ajouter
              </button>
            ) : (
              <span className="text-sm text-red-500 font-medium">Rupture</span>
            )}
          </div>
        </div>
      </div>
    </Link>
  );
}
