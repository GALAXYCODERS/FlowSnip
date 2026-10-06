"use strict";

const escapeHTML = text => text.replace(/[&<>"']/g, character => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
}[character]));

function mathToken(source, block) {
  const delimiters = block ? [["$$", "$$"], ["\\[", "\\]"]] : [["\\(", "\\)"], ["$", "$"]];
  for (const [opening, closing] of delimiters) {
    if (!source.startsWith(opening) || (opening === "$" && source.startsWith("$$"))) continue;
    const end = source.indexOf(closing, opening.length);
    if (end < 0) continue;
    const expression = source.slice(opening.length, end);
    if (!expression.trim() || (!block && expression.includes("\n"))) continue;
    if (opening === "$" && (/^\s|\s$/.test(expression))) continue;
    return { type: block ? "displayMath" : "inlineMath", raw: source.slice(0, end + closing.length), expression, block };
  }
  if (block) {
    const match = /^\[\s*\n([\s\S]*?)\n\]\s*(?:\n|$)/.exec(source);
    if (match && /\\[a-zA-Z]|[=^_]/.test(match[1])) {
      return { type: "displayMath", raw: match[0], expression: match[1], block: true };
    }
  } else {
    const match = /^\(([^\n()]*\\[a-zA-Z][^\n()]*)\)/.exec(source);
    if (match) return { type: "inlineMath", raw: match[0], expression: match[1], block: false };
  }
}

function renderMath(token) {
  try {
    if (token.expression.length > 8000) throw new Error("Equation too long");
    return katex.renderToString(token.expression, {
      displayMode: token.block, throwOnError: true, trust: false,
      maxExpand: 1000, maxSize: 20, output: "htmlAndMathml"
    });
  } catch {
    return `<${token.block ? "pre" : "code"} class="math-fallback">${escapeHTML(token.raw)}</${token.block ? "pre" : "code"}>`;
  }
}

marked.use({
  gfm: true,
  renderer: {
    html: token => escapeHTML(token.text),
    image: token => escapeHTML(token.text || "")
  },
  extensions: [
    { name: "displayMath", level: "block", start: source => source.search(/\$\$|\\\[|^\[\s*\n/m),
      tokenizer: source => mathToken(source, true), renderer: renderMath },
    { name: "inlineMath", level: "inline", start: source => source.search(/\\\(|\$|\([^\n()]*\\[a-zA-Z]/),
      tokenizer: source => mathToken(source, false), renderer: renderMath }
  ]
});

window.renderAnswer = text => {
  const html = marked.parse(String(text).slice(0, 64000));
  document.getElementById("answer").innerHTML = DOMPurify.sanitize(html, {
    USE_PROFILES: { html: true, mathMl: true, svg: true },
    FORBID_TAGS: ["style", "script", "img", "iframe", "object", "form", "input", "button"],
    FORBID_ATTR: ["id", "name"]
  });
};

const reportHeight = () => {
  window.webkit?.messageHandlers?.answerHeight?.postMessage(document.getElementById("answer").getBoundingClientRect().height);
};
new ResizeObserver(reportHeight).observe(document.getElementById("answer"));
document.fonts.ready.then(reportHeight);