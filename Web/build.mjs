import { build } from 'esbuild';
import { cpSync, mkdirSync, rmSync, existsSync, readdirSync } from 'node:fs';
rmSync('dist', { recursive: true, force: true });
mkdirSync('dist/clang', { recursive: true });
// Workers + engine bundled as ES modules.
await build({
  entryPoints: { 'compile.worker': 'src/compile.worker.js', 'run.worker': 'src/run.worker.js', 'engine': 'src/engine.js', 'app': 'src/app.js', 'engine-host': 'src/engine-host.js', 'reader': 'src/reader.js' }
    ,
  bundle: true, format: 'esm', outdir: 'dist', platform: 'browser', target: 'safari15',
  external: ['./clang/bundle.js'], minify: false, logLevel: 'info',
  entryNames: '[name]',
}).catch(() => process.exit(1));
cpSync('node_modules/@yowasp/clang/gen', 'dist/clang', { recursive: true });
// KaTeX stylesheet + woff2 fonts only (smaller; WebKit supports woff2).
mkdirSync('dist/katex/fonts', { recursive: true });
cpSync('node_modules/katex/dist/katex.min.css', 'dist/katex/katex.min.css');
for (const f of readdirSync('node_modules/katex/dist/fonts')) if (f.endsWith('.woff2')) cpSync('node_modules/katex/dist/fonts/' + f, 'dist/katex/fonts/' + f);
if (existsSync('static')) cpSync('static', 'dist', { recursive: true });
