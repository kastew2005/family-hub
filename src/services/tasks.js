import { supabase } from './supabase.js';

export const TASK_CATEGORIES = ['Список покупок','Уборка и порядок','Домашние обязанности','Поручения','Ремонт и обслуживание','Семейные дела','Учёба и работа','Другое'];
export const PRIORITIES = [{value:'normal',label:'Обычный'},{value:'important',label:'Важный'},{value:'urgent',label:'Срочный'}];
export const STATUSES = [{value:'new',label:'Новая'},{value:'in_progress',label:'В работе'},{value:'completed',label:'Выполнена'},{value:'cancelled',label:'Отменена'}];
const needClient = () => { if (!supabase) throw new Error('Подключите Supabase, чтобы работать с семейными данными.'); };
export async function listTasks(familyId) { needClient(); const [{data,error},{data:comments,error:commentError}]=await Promise.all([supabase.from('tasks').select('*').eq('family_id',familyId).order('created_at',{ascending:false}),supabase.from('item_comments').select('entity_id').eq('family_id',familyId).eq('entity_type','task')]); if(error)throw error;if(commentError)throw commentError;const counts=new Map();for(const c of comments||[])counts.set(c.entity_id,(counts.get(c.entity_id)||0)+1);return (data||[]).map(t=>({...t,comment_count:counts.get(t.id)||0})); }
export async function listCategories(familyId) { needClient(); const {data,error}=await supabase.from('task_categories').select('*').eq('family_id',familyId).order('sort_order'); if(error)throw error; return (data||[]).length ? data : TASK_CATEGORIES.map((name,i)=>({id:null,name,is_default:true,sort_order:(i+1)*10})); }
export async function createCategory({familyId,userId,name}) { needClient(); const {data:existing,error:readError}=await supabase.from('task_categories').select('sort_order').eq('family_id',familyId).order('sort_order',{ascending:false}).limit(1); if(readError)throw readError; const sortOrder=(existing?.[0]?.sort_order??80)+10; const {data,error}=await supabase.from('task_categories').insert({family_id:familyId,created_by:userId,name:name.trim(),is_default:false,sort_order:sortOrder}).select().single(); if(error)throw error; return data; }
export async function saveTask({familyId,userId,creatorName,task}) { needClient(); const payload={family_id:familyId,created_by:userId,creator_name:creatorName,title:task.title.trim(),description:task.description||'',category_name:task.category||'Другое',assignee_id:task.assigneeId||null,due_at:task.dueAt||null,priority:task.priority||'normal',recurrence:task.recurrence||{type:'none'}}; if(task.id){ const {family_id,created_by,creator_name,...editable}=payload; const {data,error}=await supabase.from('tasks').update({...editable,updated_at:new Date().toISOString()}).eq('id',task.id).eq('version',task.version).select().single(); if(error){if(error.code==='PGRST116')throw new Error('Задача уже изменилась на другом устройстве. Обновите список и повторите.');throw error;}return data;} const {data,error}=await supabase.from('tasks').insert(payload).select().single(); if(error)throw error; return data; }
export async function setTaskStatus(task) { needClient(); const {data,error}=await supabase.rpc(task.status==='completed'?'complete_task':'reopen_task',{p_task_id:task.id}); if(error)throw error; return data; }
export async function updateTaskStatus(taskId,status) { needClient(); const {data,error}=await supabase.from('tasks').update({status}).eq('id',taskId).select().single(); if(error)throw error; return data; }
export async function toggleFavorite(taskId,value) { needClient(); const {data,error}=await supabase.from('tasks').update({is_favorite:value}).eq('id',taskId).select().single(); if(error)throw error; return data; }
export async function deleteTask(taskId) { needClient(); const {error}=await supabase.from('tasks').delete().eq('id',taskId); if(error)throw error; }
export async function listMembers(familyId) { needClient(); const {data,error}=await supabase.from('family_members').select('user_id,display_name,avatar_color,role').eq('family_id',familyId).is('removed_at',null).order('joined_at'); if(error)throw error; return data||[]; }

export async function reorderCategory({ id, sortOrder }) {
  needClient(); const { data, error } = await supabase.from('task_categories').update({ sort_order: sortOrder }).eq('id', id).select().single();
  if (error) throw error; return data;
}

export async function getFamilyStats(familyId) {
  needClient();
  const { data, error } = await supabase.from('task_completion_history').select('completed_by, completed_at').eq('family_id', familyId);
  if (error) throw error;
  const rows = data || []; const now = new Date();
  const startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const startWeek = new Date(startToday); startWeek.setDate(startWeek.getDate() - ((startWeek.getDay() + 6) % 7));
  const today = rows.filter(r => new Date(r.completed_at) >= startToday).length;
  const week = rows.filter(r => new Date(r.completed_at) >= startWeek).length;
  return { completedToday: today, completedWeek: week, totalCompleted: rows.length, achievements: [
    ...(rows.length >= 1 ? [{ title: 'Первое дело', description: 'В семье выполнена первая задача' }] : []),
    ...(rows.length >= 10 ? [{ title: 'Десять шагов', description: 'Выполнено не менее 10 задач' }] : []),
    ...(rows.length >= 50 ? [{ title: 'Слаженная команда', description: 'Выполнено не менее 50 задач' }] : [])
  ] };
}
