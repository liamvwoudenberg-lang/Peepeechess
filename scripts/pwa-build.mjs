import { readdir, readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
const assets = (await readdir("dist/assets")).map((f) => "/assets/" + f);
const files = [
  "/",
  "/index.html",
  "/manifest.webmanifest",
  "/icons/icon-192.png",
  "/icons/icon-512.png",
  "/icons/apple-touch-icon.png",
  "/pieces/legions-drawn.webp",
  "/pieces/legions-drawn.png",
  ...assets,
];
const hash = createHash("sha256");
for (const f of files)
  hash.update(await readFile("dist" + (f === "/" ? "/index.html" : f)));
const name = "sovereigns-gambit-" + hash.digest("hex").slice(0, 16);
// An update waits for existing tabs to close, so it cannot replace a live game.
await writeFile(
  "dist/sw.js",
  `const CACHE=${JSON.stringify(name)},FILES=${JSON.stringify(files)},PATHS=new Set(FILES);
self.addEventListener('install',event=>event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(FILES))));
self.addEventListener('activate',event=>event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key.startsWith('sovereigns-gambit-')&&key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',event=>{const u=new URL(event.request.url);if(event.request.method!=='GET'||u.origin!==self.location.origin||u.pathname.startsWith('/api/')||u.pathname.startsWith('/peerjs'))return;if(event.request.mode==='navigate'){event.respondWith(caches.open(CACHE).then(cache=>cache.match('/index.html')));return;}if(PATHS.has(u.pathname))event.respondWith(caches.open(CACHE).then(async cache=>(await cache.match(u.pathname))||fetch(event.request)));});
`,
);
console.log("Offline app shell ready:", name);
