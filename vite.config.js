import { defineConfig } from 'vite';

// GitHub Pages project sites are served from /<repository>/; local preview uses /.
const base = process.env.GITHUB_ACTIONS === 'true' ? '/family-hub/' : (process.env.VITE_BASE_PATH || '/');
export default defineConfig({ base, build: { outDir: 'dist', sourcemap: false, emptyOutDir: true } });
