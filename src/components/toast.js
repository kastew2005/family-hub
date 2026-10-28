let timer;
export function toast(message, type = 'info') {
  let el = document.querySelector('.toast-region');
  if (!el) { el = document.createElement('div'); el.className = 'toast-region'; el.setAttribute('role', 'status'); el.setAttribute('aria-live', 'polite'); document.body.append(el); }
  el.textContent = message; el.dataset.type = type; el.classList.add('is-visible');
  clearTimeout(timer); timer = setTimeout(() => el.classList.remove('is-visible'), 3400);
}
