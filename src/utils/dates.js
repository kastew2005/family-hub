export function greeting(date = new Date()) {
  const hour = date.getHours();
  return hour < 5 ? 'Доброй ночи' : hour < 12 ? 'Доброе утро' : hour < 18 ? 'Добрый день' : 'Добрый вечер';
}
export function formatDate(date = new Date(), options = { day: 'numeric', month: 'long', weekday: 'long' }) {
  return new Intl.DateTimeFormat('ru-RU', options).format(date);
}
export function formatTime(value) {
  return new Intl.DateTimeFormat('ru-RU', { hour: '2-digit', minute: '2-digit' }).format(new Date(value));
}
