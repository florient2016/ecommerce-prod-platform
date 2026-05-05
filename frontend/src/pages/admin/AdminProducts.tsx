// src/pages/admin/AdminProducts.tsx
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { productsApi } from '../../lib/api';
import { useState } from 'react';
import { Plus, Pencil, Trash2, Loader2, X } from 'lucide-react';
import { useForm } from 'react-hook-form';

export default function AdminProducts() {
  const qc = useQueryClient();
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<any>(null);
  const { register, handleSubmit, reset, setValue } = useForm();

  const { data, isLoading } = useQuery({ queryKey: ['admin-products'], queryFn: () => productsApi.list({ limit: 50 }) });
  const products = data?.data?.data || [];

  const createMut = useMutation({ mutationFn: (d: any) => productsApi.create(d), onSuccess: () => { qc.invalidateQueries({ queryKey: ['admin-products'] }); setShowForm(false); reset(); } });
  const updateMut = useMutation({ mutationFn: ({ id, data }: any) => productsApi.update(id, data), onSuccess: () => { qc.invalidateQueries({ queryKey: ['admin-products'] }); setShowForm(false); setEditing(null); reset(); } });
  const deleteMut = useMutation({ mutationFn: (id: string) => productsApi.delete(id), onSuccess: () => qc.invalidateQueries({ queryKey: ['admin-products'] }) });

  const openEdit = (p: any) => {
    setEditing(p);
    setValue('name', p.name);
    setValue('description', p.description);
    setValue('price', p.price);
    setValue('stock', p.stock);
    setValue('imageUrl', p.imageUrl || '');
    setValue('categoryId', p.categoryId);
    setShowForm(true);
  };

  const onSubmit = (data: any) => {
    if (editing) updateMut.mutate({ id: editing.id, data });
    else createMut.mutate(data);
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold text-gray-900">Gestion Produits</h1>
        <button onClick={() => { setEditing(null); reset(); setShowForm(true); }}
          className="flex items-center gap-2 bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700">
          <Plus className="h-4 w-4" /> Nouveau produit
        </button>
      </div>

      {/* Form Modal */}
      {showForm && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl shadow-xl w-full max-w-lg p-6">
            <div className="flex justify-between items-center mb-6">
              <h2 className="text-lg font-bold">{editing ? 'Modifier' : 'Nouveau'} produit</h2>
              <button onClick={() => setShowForm(false)}><X className="h-5 w-5 text-gray-400" /></button>
            </div>
            <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
              {[
                { name: 'name', label: 'Nom', type: 'text' },
                { name: 'price', label: 'Prix (€)', type: 'number' },
                { name: 'stock', label: 'Stock', type: 'number' },
                { name: 'categoryId', label: 'ID Catégorie', type: 'text' },
                { name: 'imageUrl', label: 'URL Image', type: 'url', required: false },
              ].map(f => (
                <div key={f.name}>
                  <label className="block text-sm font-medium text-gray-700 mb-1">{f.label}</label>
                  <input type={f.type} {...register(f.name, { required: f.required !== false })}
                    className="w-full border border-gray-300 rounded-lg px-3 py-2 focus:ring-2 focus:ring-blue-500 focus:border-transparent" />
                </div>
              ))}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Description</label>
                <textarea {...register('description', { required: true })} rows={3}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 focus:ring-2 focus:ring-blue-500 focus:border-transparent" />
              </div>
              <div className="flex gap-3 pt-2">
                <button type="submit" className="flex-1 bg-blue-600 text-white py-2 rounded-lg hover:bg-blue-700 font-medium">
                  {editing ? 'Modifier' : 'Créer'}
                </button>
                <button type="button" onClick={() => setShowForm(false)} className="flex-1 border border-gray-300 py-2 rounded-lg hover:bg-gray-50">
                  Annuler
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {isLoading ? (
        <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-blue-600" /></div>
      ) : (
        <div className="bg-white rounded-xl border border-gray-100 overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-gray-500">
              <tr>
                <th className="text-left px-4 py-3 font-medium">Produit</th>
                <th className="text-left px-4 py-3 font-medium">Catégorie</th>
                <th className="text-right px-4 py-3 font-medium">Prix</th>
                <th className="text-right px-4 py-3 font-medium">Stock</th>
                <th className="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-50">
              {products.map((p: any) => (
                <tr key={p.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-3">
                      {p.imageUrl && <img src={p.imageUrl} alt={p.name} className="h-10 w-10 rounded object-cover" />}
                      <span className="font-medium text-gray-900">{p.name}</span>
                    </div>
                  </td>
                  <td className="px-4 py-3 text-gray-500">{p.category?.name}</td>
                  <td className="px-4 py-3 text-right font-medium">{Number(p.price).toFixed(2)} €</td>
                  <td className="px-4 py-3 text-right">
                    <span className={`px-2 py-0.5 rounded text-xs font-medium ${p.stock > 0 ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-700'}`}>
                      {p.stock}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-right">
                    <div className="flex justify-end gap-2">
                      <button onClick={() => openEdit(p)} className="p-1.5 text-gray-400 hover:text-blue-600 hover:bg-blue-50 rounded">
                        <Pencil className="h-4 w-4" />
                      </button>
                      <button onClick={() => { if (confirm('Supprimer ?')) deleteMut.mutate(p.id); }}
                        className="p-1.5 text-gray-400 hover:text-red-600 hover:bg-red-50 rounded">
                        <Trash2 className="h-4 w-4" />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
