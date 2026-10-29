function validDate(value) {
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (value === null || value === undefined || value === '') return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

export function greeting(value = new Date()) {
  const date = validDate(value) || new Date();
  const hour = date.getHours();
  return hour < 5 ? 'Доброй ночи' : hour < 12 ? 'Доброе утро' : hour < 18 ? 'Добрый день' : 'Добрый вечер';
}

export function formatDate(value = new Date(), options = { day: 'numeric', month: 'long', weekday: 'long' }) {
  const date = validDate(value);
  if (!date) return 'Дата не указана';
  try {
    return new Intl.DateTimeFormat('ru-RU', options).format(date);
  } catch {
    return 'Дата не указана';
  }
}

export function formatTime(value) {
  const date = validDate(value);
  if (!date) return '—';
  try {
    return new Intl.DateTimeFormat('ru-RU', { hour: '2-digit', minute: '2-digit' }).format(date);
  } catch {
    return '—';
  }
}

export function toDateInputValue(value) {
  const date = validDate(value);
  if (!date) return '';
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}
