import { supabase } from './supabase.js';

export async function signUp({ email, password, name }) {
  if (!supabase) throw new Error('Сначала настройте подключение Supabase в файле .env.');
  const { data, error } = await supabase.auth.signUp({ email: email.trim(), password, options: { data: { display_name: name.trim() } } });
  if (error) throw error;
  return data;
}
export async function signIn({ email, password }) {
  if (!supabase) throw new Error('Сначала настройте подключение Supabase в файле .env.');
  const { data, error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
  if (error) throw error;
  return data;
}
export async function signOut() {
  if (!supabase) return;
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}
export async function getSession() {
  if (!supabase) return null;
  const { data, error } = await supabase.auth.getSession();
  if (error) throw error;
  return data.session;
}
