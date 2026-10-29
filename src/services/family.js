import { supabase } from './supabase.js';

export async function getMyMembership() {
  if (!supabase) throw new Error('Supabase не настроен.');
  const { data: authData, error: authError } = await supabase.auth.getUser();
  if (authError) throw authError;
  const userId = authData.user?.id;
  if (!userId) return null;
  const { data, error } = await supabase.from('family_members').select('family_id, role, display_name, avatar_color, joined_at, families(id, name, created_at)').eq('user_id', userId).is('removed_at', null).maybeSingle();
  if (error) throw error;
  return data;
}
export async function createFamily({ name, displayName }) {
  if (!supabase) throw new Error('Supabase не настроен.');
  const { data, error } = await supabase.rpc('create_family', { p_family_name: name.trim(), p_display_name: displayName.trim() });
  if (error) throw error;
  return data;
}
export async function joinFamily({ code, displayName }) {
  if (!supabase) throw new Error('Supabase не настроен.');
  const { data, error } = await supabase.rpc('join_family_by_invite', { p_invite_code: code.trim(), p_display_name: displayName.trim() });
  if (error) throw error;
  return data;
}
export async function updateMyProfile({ displayName, avatarColor }) {
  if (!supabase) throw new Error('Supabase не настроен.');
  const { error } = await supabase.rpc('update_my_profile', { p_display_name: displayName, p_avatar_color: avatarColor ?? null });
  if (error) throw error;
  return true;
}

export async function createFamilyInvite({ expiresInHours = 72, maxUses = 1 } = {}) {
  if (!supabase) throw new Error('Supabase не настроен.');
  const { data, error } = await supabase.rpc('create_family_invite', { p_expires_in_hours: expiresInHours, p_max_uses: maxUses });
  if (error) throw error;
  return data;
}
export async function removeFamilyMember(userId) {
  if (!supabase) throw new Error('Supabase не настроен.');
  const { data, error } = await supabase.rpc('remove_family_member', { p_member_user_id: userId });
  if (error) throw error;
  return data;
}
