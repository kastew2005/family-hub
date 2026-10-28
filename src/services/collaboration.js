import { generateRecurringDates } from '../utils/recurrence.js';
import { supabase } from './supabase.js';
const need=()=>{if(!supabase)throw new Error('Supabase не настроен.');};
export async function listComments(familyId,type,id){need();const [{data,error},{data:reactions,error:reactionError}]=await Promise.all([supabase.from('item_comments').select('*').eq('family_id',familyId).eq('entity_type',type).eq('entity_id',id).order('created_at'),supabase.from('comment_reactions').select('comment_id,reaction,user_id').eq('family_id',familyId)]);if(error)throw error;if(reactionError)throw reactionError;const counts=new Map();for(const r of reactions||[]){const key=r.comment_id;const row=counts.get(key)||{};row[r.reaction]=(row[r.reaction]||0)+1;counts.set(key,row);}return (data||[]).map(c=>({...c,reactions:counts.get(c.id)||{}}));}
export async function addComment({familyId,type,id,userId,name,color,body,parentId=null}){need();const {data,error}=await supabase.from('item_comments').insert({family_id:familyId,entity_type:type,entity_id:id,author_id:userId,author_name:name,author_avatar_color:color||'#777D61',body:body.trim(),parent_id:parentId}).select().single();if(error)throw error;return data;}
export async function editComment(id,body){need();const {data,error}=await supabase.from('item_comments').update({body:body.trim(),edited_at:new Date().toISOString()}).eq('id',id).select().single();if(error)throw error;return data;}
export async function deleteComment(id){need();const {error}=await supabase.from('item_comments').delete().eq('id',id);if(error)throw error;}
export async function reactComment({commentId,familyId,userId,reaction,active}){need();if(active){const {error}=await supabase.from('comment_reactions').delete().eq('comment_id',commentId).eq('user_id',userId).eq('reaction',reaction);if(error)throw error;}else{const {error}=await supabase.from('comment_reactions').insert({comment_id:commentId,family_id:familyId,user_id:userId,reaction});if(error)throw error;}}
export async function toggleMyReaction({commentId,familyId,userId,reaction}){need();const {data,error}=await supabase.from('comment_reactions').select('id').eq('comment_id',commentId).eq('user_id',userId).eq('reaction',reaction).maybeSingle();if(error)throw error;return reactComment({commentId,familyId,userId,reaction,active:Boolean(data)});}
export async function listActivity(familyId,limit=100){need();const {data,error}=await supabase.from('family_events').select('*').eq('family_id',familyId).order('created_at',{ascending:false}).limit(limit);if(error)throw error;return data||[];}
export async function listNotifications(){need();const {data,error}=await supabase.from('notifications').select('*').order('created_at',{ascending:false}).limit(100);if(error)throw error;return data||[];}
export async function markNotificationRead(id){need();const {error}=await supabase.rpc('mark_notification_read',{p_notification_id:id});if(error)throw error;}
export async function listCalendar(familyId,start,end){need();const {data,error}=await supabase.from('calendar_events').select('*').eq('family_id',familyId).gte('starts_at',start).lt('starts_at',end).order('starts_at');if(error)throw error;return data||[];}
export async function saveCalendar({familyId,userId,creatorName,event}){need();const recurrence=event.recurrence||{type:'none'};const p={family_id:familyId,created_by:userId,creator_name:creatorName,title:event.title.trim(),description:event.description||'',event_type:event.type||'family',starts_at:event.startsAt,ends_at:event.endsAt||null,all_day:Boolean(event.allDay),recurrence,participant_ids:event.participantIds||[]};const {data,error}=event.id?await supabase.from('calendar_events').update(p).eq('id',event.id).select().single():await supabase.from('calendar_events').insert(p).select().single();if(error)throw error;if(!event.id&&recurrence.type&&recurrence.type!=='none'){const children=generateRecurringDates(event.startsAt,recurrence.type,12).map(next=>({...p,recurrence_root_id:data.id,recurrence_key:next.toISOString(),starts_at:next.toISOString()}));if(children.length){const {error:repeatError}=await supabase.from('calendar_events').upsert(children,{onConflict:'family_id,recurrence_root_id,recurrence_key',ignoreDuplicates:true});if(repeatError)throw repeatError;}}return data;}

export async function listFamilyNotes(familyId) {
  need(); const { data, error } = await supabase.from('family_notes').select('*').eq('family_id', familyId).order('updated_at', { ascending: false });
  if (error) throw error; return data || [];
}
export async function saveFamilyNote({ familyId, userId, note }) {
  need(); const payload = { family_id: familyId, title: note.title.trim(), body: note.body.trim(), created_by: userId, updated_by: userId };
  const result = note.id ? await supabase.from('family_notes').update({ title: payload.title, body: payload.body, updated_by: userId }).eq('id', note.id).select().single() : await supabase.from('family_notes').insert(payload).select().single();
  if (result.error) throw result.error; return result.data;
}
export async function deleteFamilyNote(id) {
  need(); const { error } = await supabase.from('family_notes').delete().eq('id', id); if (error) throw error;
}
export async function listTaskTemplates(familyId) {
  need(); const { data, error } = await supabase.from('task_templates').select('*').eq('family_id', familyId).order('created_at', { ascending: false });
  if (error) throw error; return data || [];
}
export async function saveTaskTemplate({ familyId, userId, template }) {
  need(); const { data, error } = await supabase.from('task_templates').insert({ family_id: familyId, created_by: userId, title: template.title.trim(), description: template.description || '', category_name: template.category_name || 'Другое', priority: template.priority || 'normal', recurrence: template.recurrence || { type: 'none' } }).select().single();
  if (error) throw error; return data;
}

export async function updateNotificationSettings(settings) {
  need(); const { data, error } = await supabase.from('profiles').update({ notification_settings: settings }).select('notification_settings').single();
  if (error) throw error; return data.notification_settings;
}
