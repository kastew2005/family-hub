export function generateRecurringDates(startValue, typeOrConfig, count = 12) {
  const start = new Date(startValue);
  const config = typeof typeOrConfig === 'string' ? { type: typeOrConfig } : (typeOrConfig || { type: 'none' });
  const type = config.type;
  if (Number.isNaN(start.getTime()) || !Number.isInteger(count) || count < 0 || count > 120) throw new Error('Некорректные параметры повторения.');
  if (!['daily', 'weekly', 'monthly', 'weekdays'].includes(type)) return [];
  const dates = [];
  if (type === 'weekdays') {
    const days = [...new Set((config.days || []).map(Number).filter(day => Number.isInteger(day) && day >= 0 && day <= 6))];
    if (!days.length) return [];
    const cursor = new Date(start);
    for (let step = 0; step < 366 && dates.length < count; step++) {
      cursor.setDate(cursor.getDate() + 1);
      if (days.includes(cursor.getDay())) dates.push(new Date(cursor));
    }
    return dates;
  }
  for (let i = 1; i <= count; i++) {
    const next = new Date(start);
    if (type === 'daily') next.setDate(next.getDate() + i);
    if (type === 'weekly') next.setDate(next.getDate() + 7 * i);
    if (type === 'monthly') {
      const day = start.getDate(); next.setDate(1); next.setMonth(start.getMonth() + i);
      const lastDay = new Date(next.getFullYear(), next.getMonth() + 1, 0).getDate(); next.setDate(Math.min(day, lastDay));
    }
    dates.push(next);
  }
  return dates;
}
export function calculateShoppingTotal(items = []) {
  return items.reduce((sum, item) => item.estimated_price == null || item.archived_at || item.bought_at ? sum : sum + Number(item.estimated_price) * Number(item.quantity || 1), 0);
}
