/* Tibetan-CAT-Tool — Logo marks (geometric only; no thangka illustration) */
window.MandalaMark = function (size, color) {
  // Octagonal mandala-derived geometric mark — section divider glyph
  size = size || 56;
  color = color || "currentColor";
  return `
  <svg viewBox="0 0 56 56" width="${size}" height="${size}" aria-hidden="true">
    <g fill="none" stroke="${color}" stroke-width="1.4">
      <circle cx="28" cy="28" r="24"/>
      <circle cx="28" cy="28" r="16"/>
      <circle cx="28" cy="28" r="3" fill="${color}"/>
      <g>
        <line x1="28" y1="4"  x2="28" y2="52"/>
        <line x1="4"  y1="28" x2="52" y2="28"/>
        <line x1="11" y1="11" x2="45" y2="45"/>
        <line x1="45" y1="11" x2="11" y2="45"/>
      </g>
    </g>
  </svg>`;
};

/* ─── LOGO 01 ─────────────────────────────────────────────
   "Endless knot caret" — the dpal be'u (endless knot) reduced
   to a square Emacs-cursor-like mark. Buddhist symbol +
   blinking-cursor metaphor.
*/
window.LogoEndlessKnot = function (size) {
  size = size || 240;
  return `
  <svg viewBox="0 0 240 240" width="${size}" height="${size}" aria-label="Endless-knot caret">
    <rect x="6" y="6" width="228" height="228" rx="8" fill="none" stroke="#5C1A1B" stroke-width="3"/>
    <g fill="none" stroke="#5C1A1B" stroke-width="10" stroke-linecap="square" stroke-linejoin="miter">
      <path d="M 70 70 L 170 70 L 170 170 L 70 170 Z"/>
      <path d="M 95 45 L 95 195"/>
      <path d="M 145 45 L 145 195"/>
      <path d="M 45 95 L 195 95"/>
      <path d="M 45 145 L 195 145"/>
    </g>
    <rect x="115" y="208" width="14" height="22" fill="#D97A1F"/>
  </svg>`;
};

/* ─── LOGO 02 ─────────────────────────────────────────────
   "OṂ in brackets" — the Tibetan syllable ༀ inside Emacs-style
   square brackets. Syllable-as-program metaphor.
*/
window.LogoOmBrackets = function (size) {
  size = size || 240;
  return `
  <svg viewBox="0 0 320 200" width="${size}" height="${(size*200/320)}" aria-label="Om in brackets">
    <g fill="none" stroke="#5C1A1B" stroke-width="8" stroke-linecap="square">
      <polyline points="60,30 30,30 30,170 60,170"/>
      <polyline points="260,30 290,30 290,170 260,170"/>
    </g>
    <text x="160" y="142" text-anchor="middle"
          font-family="Noto Serif Tibetan, Jomolhari, serif"
          font-size="150" fill="#5C1A1B">ༀ</text>
    <rect x="304" y="92" width="10" height="16" fill="#D97A1F"/>
  </svg>`;
};

/* ─── LOGO 03 ─────────────────────────────────────────────
   "Wheel-as-cursor" — Dharmachakra reinterpreted as a
   spinning text-cursor / spinner. Eight spokes preserved.
*/
window.LogoWheelCursor = function (size) {
  size = size || 240;
  return `
  <svg viewBox="0 0 240 240" width="${size}" height="${size}" aria-label="Wheel cursor">
    <circle cx="120" cy="120" r="86" fill="none" stroke="#5C1A1B" stroke-width="6"/>
    <circle cx="120" cy="120" r="60" fill="none" stroke="#5C1A1B" stroke-width="3"/>
    <circle cx="120" cy="120" r="14" fill="#5C1A1B"/>
    <g stroke="#5C1A1B" stroke-width="6" stroke-linecap="butt">
      <line x1="120" y1="34"  x2="120" y2="78"/>
      <line x1="120" y1="162" x2="120" y2="206"/>
      <line x1="34"  y1="120" x2="78"  y2="120"/>
      <line x1="162" y1="120" x2="206" y2="120"/>
      <line x1="59"  y1="59"  x2="91"  y2="91"/>
      <line x1="149" y1="149" x2="181" y2="181"/>
      <line x1="181" y1="59"  x2="149" y2="91"/>
      <line x1="91"  y1="149" x2="59"  y2="181"/>
    </g>
    <rect x="113" y="216" width="14" height="20" fill="#D97A1F"/>
  </svg>`;
};

/* ─── LOGO 04 ─────────────────────────────────────────────
   "Pecha folio" — long horizontal pecha shape with the
   Tibetan syllable བོད (Bod = "Tibet") and a monospace
   bracket. Most literal of the four.
*/
window.LogoPechaFolio = function (size) {
  size = size || 320;
  return `
  <svg viewBox="0 0 360 160" width="${size}" height="${(size*160/360)}" aria-label="Pecha folio">
    <rect x="6" y="20" width="348" height="120" fill="#EADDC2" stroke="#5C1A1B" stroke-width="3"/>
    <line x1="6"  y1="36"  x2="354" y2="36"  stroke="#5C1A1B" stroke-width="1"/>
    <line x1="6"  y1="124" x2="354" y2="124" stroke="#5C1A1B" stroke-width="1"/>
    <circle cx="44" cy="80" r="10" fill="none" stroke="#5C1A1B" stroke-width="2"/>
    <circle cx="316" cy="80" r="10" fill="none" stroke="#5C1A1B" stroke-width="2"/>
    <text x="180" y="100" text-anchor="middle"
          font-family="Noto Serif Tibetan, Jomolhari, serif"
          font-size="56" fill="#5C1A1B">བོད་ཡིག</text>
  </svg>`;
};

/* Wordmark — used on title slide and header */
window.Wordmark = function (variant) {
  variant = variant || "dark";
  const fg = variant === "light" ? "#F2E8D5" : "#1A1614";
  const accent = "#D97A1F";
  const sub = variant === "light" ? "#D4A85C" : "#5C1A1B";
  return `
  <div style="font-family: var(--mono); display: flex; flex-direction: column; gap: 4px;">
    <div style="font-family: var(--serif); font-size: 64px; line-height: 1; font-weight: 500; color:${fg}; letter-spacing: -0.01em;">
      Tibetan<span style="color:${accent};">·</span>CAT<span style="color:${accent};">·</span>Tool
    </div>
    <div style="font-family: var(--mono); font-size: 22px; letter-spacing: 0.22em; text-transform: uppercase; color:${sub};">
      a translator's environment for Emacs
    </div>
  </div>`;
};
