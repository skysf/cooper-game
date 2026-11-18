import { defineConfig } from 'vite';

export default defineConfig({
  root: 'web',
  base: '/a/',
  build: { outDir: '../dist/a', emptyOutDir: true },
});
