export function openModal({ title, content, onSubmit, submitLabel = 'Продолжить' }) {
  return new Promise(resolve => {
    const previousFocus = document.activeElement;
    const previousOverflow = document.body.style.overflow;
    const overlay = document.createElement('div'); overlay.className = 'modal-backdrop';
    const dialog = document.createElement('section'); dialog.className = 'modal-sheet'; dialog.setAttribute('role', 'dialog'); dialog.setAttribute('aria-modal', 'true');
    const heading = document.createElement('h2'); heading.id = 'modal-title'; heading.textContent = title;
    dialog.setAttribute('aria-labelledby', heading.id);
    document.body.style.overflow = 'hidden';
    const close = document.createElement('button'); close.type = 'button'; close.className = 'icon-button'; close.setAttribute('aria-label', 'Закрыть'); close.textContent = '×';
    const form = document.createElement('form'); form.className = 'form-stack';
    form.innerHTML = content;
    const shoppingMode = form.querySelector('select[name="shopping-mode"]');
    const shoppingAdvanced = form.querySelector('.shopping-advanced-fields');
    const syncShoppingMode = () => {
      if (shoppingAdvanced && shoppingMode) shoppingAdvanced.hidden = shoppingMode.value !== 'advanced';
    };
    shoppingMode?.addEventListener('change', syncShoppingMode);
    syncShoppingMode();
    const actions = document.createElement('div'); actions.className = 'modal-actions';
    const cancel = document.createElement('button'); cancel.type = 'button'; cancel.className = 'button button-secondary'; cancel.textContent = 'Отмена';
    const submit = document.createElement('button'); submit.type = 'submit'; submit.className = 'button button-primary'; submit.textContent = submitLabel;
    actions.append(cancel, submit);
    // Keep the action buttons inside the form so the submit event fires on every device.
    form.append(actions);
    dialog.append(close, heading, form); overlay.append(dialog); document.body.append(overlay);
    let finished = false;
    const finish = value => {
      if (finished) return;
      finished = true;
      document.removeEventListener('keydown', onKeydown);
      overlay.remove();
      document.body.style.overflow = previousOverflow;
      if (previousFocus?.isConnected) previousFocus.focus({ preventScroll: true });
      resolve(value);
    };
    const onKeydown = e => {
      if (e.key === 'Escape') { e.preventDefault(); finish(null); return; }
      if (e.key !== 'Tab') return;
      const focusable = [...dialog.querySelectorAll('button:not(:disabled),input:not(:disabled),textarea:not(:disabled),select:not(:disabled),a[href],[tabindex]:not([tabindex="-1"])')].filter(el => !el.hidden && el.getAttribute('aria-hidden') !== 'true');
      if (!focusable.length) { e.preventDefault(); dialog.focus(); return; }
      const firstEl = focusable[0], lastEl = focusable[focusable.length - 1];
      if (e.shiftKey && document.activeElement === firstEl) { e.preventDefault(); lastEl.focus(); }
      else if (!e.shiftKey && document.activeElement === lastEl) { e.preventDefault(); firstEl.focus(); }
    };
    document.addEventListener('keydown', onKeydown);
    close.addEventListener('click', () => finish(null)); cancel.addEventListener('click', () => finish(null));
    overlay.addEventListener('click', e => { if (e.target === overlay) finish(null); });
    form.addEventListener('submit', async e => {
      e.preventDefault();
      if (submit.disabled) return;
      submit.disabled = true; submit.textContent = 'Подождите…';
      try {
        finish(await onSubmit(new FormData(form)));
      } catch (error) {
        let note = form.querySelector('.form-error');
        if (!note) { note = document.createElement('p'); note.className = 'form-error'; form.append(note); }
        note.textContent = error.message || 'Не удалось выполнить действие.';
        submit.disabled = false; submit.textContent = submitLabel;
      }
    });
    const first = form.querySelector('input,textarea,select'); if (first) setTimeout(() => first.focus(), 30);
  });
}
