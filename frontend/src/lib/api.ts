// src/lib/api.ts
import axios from 'axios';

const API_URL = import.meta.env.VITE_API_URL || 'https://api.itssolutions.it';

export const api = axios.create({
  baseURL: `${API_URL}/api/v1`,
  timeout: 15000,
  headers: { 'Content-Type': 'application/json' },
});

// Attach JWT token to every request
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('token');
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

// Handle 401
api.interceptors.response.use(
  (res) => res,
  (err) => {
    if (err.response?.status === 401) {
      localStorage.removeItem('token');
      window.location.href = '/login';
    }
    return Promise.reject(err);
  },
);

// Auth
export const authApi = {
  register: (data: any) => api.post('/auth/register', data),
  login: (data: any) => api.post('/auth/login', data),
};

// Products
export const productsApi = {
  list: (params?: any) => api.get('/products', { params }),
  get: (id: string) => api.get(`/products/${id}`),
  create: (data: any) => api.post('/products', data),
  update: (id: string, data: any) => api.put(`/products/${id}`, data),
  delete: (id: string) => api.delete(`/products/${id}`),
};

// Cart
export const cartApi = {
  get: () => api.get('/cart'),
  upsert: (productId: string, quantity: number) => api.post('/cart', { productId, quantity }),
};

// Orders
export const ordersApi = {
  create: (data: any) => api.post('/orders', data),
  list: () => api.get('/orders'),
  adminList: (params?: any) => api.get('/admin/orders', { params }),
  updateStatus: (id: string, status: string) => api.patch(`/admin/orders/${id}/status`, { status }),
};

// Users
export const usersApi = {
  me: () => api.get('/users/me'),
  list: (params?: any) => api.get('/users', { params }),
};
