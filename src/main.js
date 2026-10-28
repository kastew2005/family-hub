import './styles/tokens.css';
import './styles/base.css';
import './styles/layout.css';
import './styles/components.css';
import './styles/mobile.css';
import { startApp } from './app.js';
startApp().catch(error => {
  const app = document.querySelector('#app');
  app.textContent = `Не удалось запустить Family Hub: ${error.message}`;
  app.className = 'fatal-error';
});
if ('serviceWorker' in navigator && import.meta.env.PROD) {
  window.addEventListener('load', () => navigator.serviceWorker.register(`${import.meta.env.BASE_URL}sw.js`).catch(() => {}));
}
