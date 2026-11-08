#!/usr/bin/env node
// Builds dist/index.html (page body without the <html>/<head>/<body> skeleton, as required by the
// claude.ai Artifact host) and dist/files.json (published path -> source path) for every runtime file.
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const html = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8');
const head = html.match(/<head>([\s\S]*?)<\/head>/i)[1];
const body = html.match(/<body>([\s\S]*?)<\/body>/i)[1];
const headKept = head
  .replace(/<meta charset[^>]*>\s*/i, '')
  .trim();
// The Artifact host does not serve .glb: models are published as <id>.glb.wasm (identical bytes, binary-safe type).
const MODEL_EXT = '.glb.wasm';
const out = `${headKept}\n<script>window.LG_MODEL_EXT = '${MODEL_EXT}';</script>\n${body.trim()}\n`;
fs.mkdirSync(path.join(ROOT, 'dist'), { recursive: true });
fs.writeFileSync(path.join(ROOT, 'dist/index.html'), out);

const files = {};
const walk = (dir) => {
  for (const f of fs.readdirSync(path.join(ROOT, dir))) {
    const rel = path.posix.join(dir, f);
    const st = fs.statSync(path.join(ROOT, rel));
    if (st.isDirectory()) walk(rel);
    else if (/\.(js|glb|jpg|png|webp|mp3|json)$/.test(f) && !/(^|\/)(NEW_ASSETS|CREDITS)/.test(f)) files[rel.endsWith('.glb') ? rel.replace(/\.glb$/, MODEL_EXT) : rel] = rel;
  }
};
walk('src');
walk('assets');
fs.writeFileSync(path.join(ROOT, 'dist/files.json'), JSON.stringify(files, null, 1));
// Split into publish batches of <= 240 files (the Artifact host accepts 255 files per publish).
const keys = Object.keys(files);
const batches = [];
for (let i = 0; i < keys.length; i += 240) batches.push(Object.fromEntries(keys.slice(i, i + 240).map((k) => [k, files[k]])));
batches.forEach((b, i) => fs.writeFileSync(path.join(ROOT, `dist/files_${i + 1}.json`), JSON.stringify(b, null, 1)));
console.log(`batches: ${batches.length}`);
const bytes = Object.values(files).reduce((s, f) => s + fs.statSync(path.join(ROOT, f)).size, 0);
console.log(`dist/index.html written; ${Object.keys(files).length} files, ${(bytes / 1e6).toFixed(1)} MB`);
