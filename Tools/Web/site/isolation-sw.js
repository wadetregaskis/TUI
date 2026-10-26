// 🖥️ TUI — A Terminal UI framework for Swift
// isolation-sw.js — makes the demo cross-origin isolated on a host that
// cannot be told to.
//
// The page needs `SharedArrayBuffer` (see index.html), which exists only on a
// cross-origin-isolated page, which a page is only when its response carries
//
//     Cross-Origin-Opener-Policy: same-origin
//     Cross-Origin-Embedder-Policy: require-corp
//
// `serve.py` sends them. GitHub Pages cannot: it has no way to set a response
// header. A service worker can, because it answers the page's requests itself
// — so this one fetches each same-origin request as normal and hands back the
// response with the two headers (and CORP, as serve.py does) added. index.html
// registers it only when the visitor presses Run on a page that is not
// isolated yet, then reloads once so the page itself arrives through it.
//
// It touches nothing cross-origin: the xterm.js scripts from the CDNs are
// loaded with `crossorigin`, so they are CORS requests that COEP accepts as
// they are. Its scope is the demo's own directory, so the rest of the site
// (the docs, the landing page) never passes through it.

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (new URL(request.url).origin !== self.location.origin) return;
  // A request the browser may only answer from its cache cannot be re-issued
  // from here (fetch() throws for it outside same-origin mode).
  if (request.cache === "only-if-cached" && request.mode !== "same-origin") return;
  event.respondWith(
    fetch(request).then((response) => {
      if (response.status === 0) return response; // opaque: nothing to add to
      const headers = new Headers(response.headers);
      headers.set("Cross-Origin-Opener-Policy", "same-origin");
      headers.set("Cross-Origin-Embedder-Policy", "require-corp");
      headers.set("Cross-Origin-Resource-Policy", "same-origin");
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers,
      });
    })
  );
});
