// src/store/cart.store.ts
import { create } from 'zustand';
import { cartApi } from '../lib/api';

interface CartItem {
  id: string;
  productId: string;
  quantity: number;
  product: { id: string; name: string; price: number; imageUrl?: string };
}

interface CartState {
  items: CartItem[];
  total: string;
  loading: boolean;
  fetchCart: () => Promise<void>;
  upsertItem: (productId: string, quantity: number) => Promise<void>;
  itemCount: () => number;
}

export const useCartStore = create<CartState>((set, get) => ({
  items: [],
  total: '0.00',
  loading: false,
  fetchCart: async () => {
    try {
      set({ loading: true });
      const res = await cartApi.get();
      set({ items: res.data.items, total: res.data.total, loading: false });
    } catch {
      set({ loading: false });
    }
  },
  upsertItem: async (productId, quantity) => {
    const res = await cartApi.upsert(productId, quantity);
    set({ items: res.data.items, total: res.data.total });
  },
  itemCount: () => get().items.reduce((sum, i) => sum + i.quantity, 0),
}));
