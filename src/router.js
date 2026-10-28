const validRoutes = new Set(['home', 'tasks', 'shopping', 'calendar', 'family', 'profile', 'discussion', 'activity']);
export function getRoute() {
  const hash = location.hash.replace(/^#\/?/, '').split('/')[0];
  return validRoutes.has(hash) ? hash : 'home';
}
export function navigate(route) {
  if (!validRoutes.has(route)) return;
  if (getRoute() === route) window.dispatchEvent(new HashChangeEvent('hashchange'));
  else location.hash = `/${route}`;
}
