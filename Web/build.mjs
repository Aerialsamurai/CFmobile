import { build } from 'esbuild';
import { cpSync, mkdirSync, rmSync, existsSync } from 'node:fs';
rmSync('dist', { recursive: true, force: true });
mkdirSync('dist/clang', { recursive: true });
// Workers + engine bundled as ES modules.
await build({
  entryPoints: { 'compile.worker': 'src/compile.worker.js', 'run.worker': 'src/run.worker.js', 'engine': 'src/engine.js', 'app': 'src/app.js', 'engine-host': 'src/engine-host.js' }
    ,
  bundle: true, format: 'esm', outdir: 'dist', platform: 'browser', target: 'safari15',
  external: ['./clang/bundle.js'], minify: false, logLevel: 'info',
  entryNames: '[name]',
}).catch(() => process.exit(1));
cpSync('node_modules/@yowasp/clang/gen', 'dist/clang', { recursive: true });
if (existsSync('static')) cpSync('static', 'dist', { recursive: true });
