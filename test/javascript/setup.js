// jsdom doesn't implement the global `CSS` object, but the storefront modules
// use `CSS.escape` (which every target browser has). Polyfill it so the tests
// run the same code path the browser does.
if (!globalThis.CSS) globalThis.CSS = {};
if (typeof globalThis.CSS.escape !== "function") {
  globalThis.CSS.escape = (value) => String(value).replace(/[^\w-]/g, (ch) => "\\" + ch);
}
