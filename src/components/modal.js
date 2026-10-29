export function openModal({ title, content, onSubmit, submitLabel = 'Продолжить' }) {
  return new Promise(resolve => {
    const overlay = document.createElement('div'); overlay.className = 'modal-backdrop';
    const dialog = document.createElement('section'); dialog.className = 'modal-sheet'; dialog.setAttribute('role', 'dialog'); dialog.setAttribute('aria-modal', 'true');
    const heading = document.createElement('h2'); heading.textContent = title;
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
    const finish = value => { overlay.remove(); resolve(value); };
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
