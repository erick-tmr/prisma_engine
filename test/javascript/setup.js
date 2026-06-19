// jsdom doesn't implement the global `CSS` object, but the storefront modules
// use `CSS.escape` (which every target browser has). Polyfill it so the tests
// run the same code path the browser does.
if (!globalThis.CSS) globalThis.CSS = {};
if (typeof globalThis.CSS.escape !== "function") {
  globalThis.CSS.escape = (value) => String(value).replace(/[^\w-]/g, (ch) => "\\" + ch);
}

if (typeof globalThis.Element !== "undefined" && !globalThis.Element.prototype.scrollIntoView) {
  globalThis.Element.prototype.scrollIntoView = () => {};
}

// jsdom doesn't implement the Web Animations API; the backoffice dashboard uses
// Element.animate for a row-click flash (cosmetic). Stub it so the same code path
// runs in tests as in the browser.
if (typeof globalThis.Element !== "undefined" && !globalThis.Element.prototype.animate) {
  globalThis.Element.prototype.animate = () => ({ cancel() {}, finish() {} });
}
