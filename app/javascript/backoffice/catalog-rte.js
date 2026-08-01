export function prettyHtml(html) {
  const normalized = (html || "")
    .replace(/\s*\n\s*/g, "")
    .replace(/<(p|ul|ol|li|blockquote|h[1-6])(\s[^>]*)?>/gi, (match) => "\n" + match)
    .replace(/<\/(p|ul|ol|li|blockquote|h[1-6])>/gi, (match) => match + "\n");
  const out = [];
  let depth = 0;
  normalized.split("\n").map((line) => line.trim()).filter(Boolean).forEach((line) => {
    if (/^<\/(ul|ol)>/i.test(line)) depth = Math.max(0, depth - 1);
    out.push("  ".repeat(line.startsWith("<li") ? depth + 1 : depth) + line);
    if (/^<(ul|ol)(\s|>)/i.test(line)) depth += 1;
  });
  return out.join("\n");
}

export function initRte(root) {
  const wrap = root.querySelector("#rte");
  if (!wrap) return null;

  const area = root.querySelector("#f-desc");
  const source = root.querySelector("#f-desc-html");
  const toolbar = root.querySelector("#rte-toolbar");
  const srcBtn = root.querySelector("#rte-source");
  const field = root.querySelector("#f-desc-field");
  const defaultTag = root.querySelector("#desc-default-tag");
  const restoreBtn = root.querySelector("#desc-restore");
  const defaultHtml = wrap.dataset.default || "";
  const state = { sourceMode: false };

  area.dataset.placeholder = "Descreva o produto…";
  configureDocument();

  const commandButtons = () => Array.from(toolbar.querySelectorAll(".rte-btn[data-cmd]"));

  function setHtml(html) {
    if (state.sourceMode) exitSource();
    area.innerHTML = html || "";
  }

  function getHtml() {
    return (state.sourceMode ? source.value : area.innerHTML).trim();
  }

  function sync() {
    if (field) field.value = getHtml();
  }

  function enterSource() {
    state.sourceMode = true;
    srcBtn.classList.add("on");
    commandButtons().forEach((button) => (button.disabled = true));
    source.value = prettyHtml(area.innerHTML);
    area.hidden = true;
    source.hidden = false;
  }

  function exitSource() {
    state.sourceMode = false;
    srcBtn.classList.remove("on");
    commandButtons().forEach((button) => (button.disabled = false));
    area.innerHTML = source.value.trim();
    area.hidden = false;
    source.hidden = true;
    sync();
  }

  function handleCommand(cmd, value) {
    area.focus();
    if (cmd === "createLink") {
      const url = window.prompt("Endereço do link (URL):", "https://");
      if (url) exec("createLink", url);
    } else {
      exec(cmd, value ? `<${value}>` : null);
    }
    sync();
  }

  toolbar.addEventListener("mousedown", (event) => {
    if (event.target.closest(".rte-btn")) event.preventDefault();
  });
  toolbar.addEventListener("click", (event) => {
    const button = event.target.closest(".rte-btn");
    if (!button) return;
    if (button === srcBtn) {
      state.sourceMode ? exitSource() : enterSource();
      return;
    }
    if (state.sourceMode) return;
    handleCommand(button.dataset.cmd, button.dataset.value);
  });
  [area, source].forEach((el) => {
    el.addEventListener("focus", () => wrap.classList.add("focus"));
    el.addEventListener("blur", () => wrap.classList.remove("focus"));
  });
  area.addEventListener("input", () => {
    if (defaultTag) defaultTag.hidden = true;
    sync();
  });
  if (restoreBtn) {
    restoreBtn.addEventListener("click", () => {
      setHtml(defaultHtml);
      if (defaultTag) defaultTag.hidden = false;
      sync();
    });
  }
  if (field && field.form) field.form.addEventListener("submit", sync, true);

  setHtml(field ? field.value : "");
  return { getHtml, setHtml, sync, isSource: () => state.sourceMode };
}

/* v8 ignore start */
function exec(cmd, value) {
  try {
    document.execCommand(cmd, false, value);
  } catch (_) {
    return;
  }
}

function configureDocument() {
  try {
    document.execCommand("defaultParagraphSeparator", false, "p");
    document.execCommand("styleWithCSS", false, false);
  } catch (_) {
    return;
  }
}

if (typeof document !== "undefined") {
  initRte(document);
}
/* v8 ignore stop */
