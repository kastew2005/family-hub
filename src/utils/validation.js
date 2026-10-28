export function requiredText(value, label, max = 80) {
  const result = String(value ?? '').trim();
  if (!result) throw new Error(`Заполните поле «${label}».`);
  if (result.length > max) throw new Error(`Поле «${label}»: максимум ${max} символов.`);
  return result;
}
export function validatePassword(value) {
  if (String(value ?? '').length < 8) throw new Error('Пароль должен содержать не менее 8 символов.');
  return value;
}
export function validateEmail(value) {
  const email = String(value ?? '').trim();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Error('Введите корректный адрес электронной почты.');
  return email;
}
