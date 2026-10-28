import test from 'node:test';
import assert from 'node:assert/strict';
import { requiredText, validateEmail, validatePassword } from './src/utils/validation.js';
import { greeting } from './src/utils/dates.js';

test('requiredText trims input and rejects empty strings', () => {
  assert.equal(requiredText('  Family  ', 'Семья'), 'Family');
  assert.throws(() => requiredText(' ', 'Семья'), /Заполните поле/);
});
test('requiredText enforces maximum length', () => assert.throws(() => requiredText('x'.repeat(5), 'Имя', 4), /максимум 4/));
test('email and password validators reject malformed values', () => {
  assert.equal(validateEmail('a@example.com'), 'a@example.com');
  assert.throws(() => validateEmail('wrong'), /корректный адрес/);
  assert.throws(() => validatePassword('123'), /не менее 8/);
});
test('greeting follows local hour', () => {
  assert.equal(greeting(new Date(2020, 0, 1, 2)), 'Доброй ночи');
  assert.equal(greeting(new Date(2020, 0, 1, 10)), 'Доброе утро');
  assert.equal(greeting(new Date(2020, 0, 1, 19)), 'Добрый вечер');
});

import { generateRecurringDates, calculateShoppingTotal } from './src/utils/recurrence.js';
import { readFileSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { readdirSync, statSync, existsSync } from 'node:fs';

test('daily, weekly and monthly recurrence produces deterministic future instances', () => {
  const start = new Date('2026-01-31T12:00:00.000Z');
  assert.equal(generateRecurringDates(start, 'daily', 2)[0].toISOString(), '2026-02-01T12:00:00.000Z');
  assert.equal(generateRecurringDates(start, 'weekly', 1)[0].toISOString(), '2026-02-07T12:00:00.000Z');
  assert.equal(generateRecurringDates(start, 'monthly', 1)[0].toISOString(), '2026-02-28T12:00:00.000Z');
  assert.deepEqual(generateRecurringDates(start, 'none', 4), []);
});

test('shopping total excludes bought, archived and unpriced items', () => {
  assert.equal(calculateShoppingTotal([
    { quantity: 2, estimated_price: 3.5 },
    { quantity: 1, estimated_price: 8, bought_at: '2026-01-01T00:00:00Z' },
    { quantity: 1, estimated_price: 4, archived_at: '2026-01-01T00:00:00Z' },
    { quantity: 1, estimated_price: null }
  ]), 7);
});

test('feature migration declares row-level security and server-owned action RPCs', () => {
  const sql = readFileSync(join(process.cwd(), 'supabase/migrations/202610280002_family_features.sql'), 'utf8');
  assert.match(sql, /alter table public\.%I enable row level security/i);
  assert.match(sql, /function public\.complete_task\(p_task_id uuid\)/i);
  assert.match(sql, /function public\.reopen_task\(p_task_id uuid\)/i);
  assert.match(sql, /function public\.set_shopping_bought\(p_item_id uuid,p_bought boolean\)/i);
  assert.match(sql, /create policy comments_update_own/i);
});

test('weekday recurrence selects only chosen weekdays and does not duplicate the start date', () => {
  const dates = generateRecurringDates('2026-10-26T12:00:00.000Z', { type: 'weekdays', days: [1, 3, 5] }, 3);
  assert.deepEqual(dates.map(d => d.toISOString()), ['2026-10-28T12:00:00.000Z', '2026-10-30T12:00:00.000Z', '2026-11-02T12:00:00.000Z']);
});

test('final migration hardens membership removal, server timestamps and notification privacy', () => {
  const sql = readFileSync(join(process.cwd(), 'supabase/migrations/202610280003_final_hardening.sql'), 'utf8');
  assert.match(sql, /function public\.remove_family_member\(p_member_user_id uuid\)/i);
  assert.match(sql, /function public\.set_shopping_archived\(p_item_id uuid,\s*p_archived boolean\)/i);
  assert.match(sql, /revoke update on public\.notifications from authenticated/i);
  assert.match(sql, /function public\.update_my_profile\(p_display_name text, p_avatar_color text default null\)/i);
});


test('relative JavaScript module imports resolve to files in the project', () => {
  const root = process.cwd(); const pending = [join(root, 'src')]; const files = [];
  while (pending.length) { const dir = pending.pop(); for (const entry of readdirSync(dir)) { const full = join(dir, entry); if (statSync(full).isDirectory()) pending.push(full); else if (full.endsWith('.js')) files.push(full); } }
  const missing = [];
  for (const file of files) { const source = readFileSync(file, 'utf8'); for (const match of source.matchAll(/(?:from\s*|import\s*)['\"](\.[^'\"]+)['\"]/g)) { const target = resolve(dirname(file), match[1]); if (!existsSync(target)) missing.push(`${file}: ${match[1]}`); } }
  assert.deepEqual(missing, []);
});

test('PWA manifest is valid and references included icon assets', () => {
  const manifest = JSON.parse(readFileSync(join(process.cwd(), 'public/manifest.webmanifest'), 'utf8'));
  assert.equal(manifest.name, 'Family Hub');
  assert.ok(manifest.icons.length >= 3);
  for (const icon of manifest.icons) assert.ok(existsSync(join(process.cwd(), 'public', icon.src.replace(/^\.\//, ''))));
});
