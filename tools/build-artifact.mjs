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
const out = `${headKept}\n${body.trim()}\n`;
fs.mkdirSync(path.join(ROOT, 'dist'), { recursive: true });
fs.writeFileSync(path.join(ROOT, 'dist/index.html'), out);

const files = {};
const walk = (dir) => {
  for (const f of fs.readdirSync(path.join(ROOT, dir))) {
    const rel = path.posix.join(dir, f);
    const st = fs.statSync(path.join(ROOT, rel));
    if (st.isDirectory()) walk(rel);
    else if (/\.(js|glb|jpg|png|webp)$/.test(f)) files[rel] = rel;
  }
};
walk('src');
walk('assets');
fs.writeFileSync(path.join(ROOT, 'dist/files.json'), JSON.stringify(files, null, 1));
const bytes = Object.values(files).reduce((s, f) => s + fs.statSync(path.join(ROOT, f)).size, 0);
console.log(`dist/index.html written; ${Object.keys(files).length} files, ${(bytes / 1e6).toFixed(1)} MB`);
