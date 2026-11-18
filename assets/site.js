// That's What She Synced: the live notch demo and its playground, the cast picker, copy buttons and the one-shot moments.
// The page is complete without this file. anime.js loads lazily, and never under Reduce Motion.

const root = document.documentElement;
const reduce = matchMedia('(prefers-reduced-motion: reduce)');
const $ = (sel, el = document) => el.querySelector(sel);
const $$ = (sel, el = document) => [...el.querySelectorAll(sel)];

const CAST = {
  scarn: ['Agent Scarn', 'Field agent, menu bar division', 'scarn'],
  goldenface: ['Goldenface', 'Antagonist. Mostly glints.', 'gold'],
  jelly: ['Jelly Stapler', 'Office supplies, suspended', 'jelly'],
  mug: ['Best Boss Mug', 'Self-awarded', 'mug'],
  beet: ['Schrute Beet', 'Root vegetable, regional', 'beet'],
};
const DANCERS = {
  boombox: ['Boombox Boss', 'Head of ceiling acoustics'],
  three: ['The Farewell Three', 'Unsynchronised, on purpose'],
  scarn: ['The Scarn', 'A dance in four instructions'],
};
const SCENES = ['idle', 'music', 'agents'];
const SCENE_MS = 5000;
const DANCES = ['three', 'boombox', 'scarn'];
// the playground's albums: palette and left glow, right glow, the VU meter's colours low to high, the dancers' three glows
const ALBUMS = [
  ['teal', 'gold', ['#22D3C5', '#F4D03F', '#F2765A'], ['#22D3C5', '#F4D03F', '#9AF5EA']],
  ['ochre', 'rust', ['#F5C451', '#DDA032', '#D24B3C'], ['#DDA032', '#D24B3C', '#FFDBA6']],
  ['pink', 'violet', ['#FF9BC8', '#FF5FA8', '#8B7BFF'], ['#FF5FA8', '#8B7BFF', '#FFD4E3']],
  ['blue', 'peach', ['#8DB8FF', '#4D90FF', '#FFB38A'], ['#4D90FF', '#FFB38A', '#D1E2FF']],
];
// the app's volume captions by band, each up to its top percentage
const BANDS = [[0, 'Jinx.'], [33, 'Inside voices.'], [66, 'Threat level: mid-tempo.'], [99, 'Corporate can hear this.'], [100, 'That’s what she synced.']];
const HOLD_MS = 2500;

// kind: the moment in the hero's notch now, if any. vol: sixteenths, as macOS steps it (9 reads 56%).
const state = { scene: 'idle', who: 'scarn', dancer: 'three', paused: reduce.matches, onScreen: true, tabVisible: !document.hidden, album: 0, vol: 9, kind: '' };

const hero = $('[data-demo="hero"]');
if (!hero) throw new Error('demo markup missing');
const heroIsl = $('.isl', hero);
const heroShot = $('.shot', hero);
const cards = $$('.card');

// restart a CSS animation by toggling its class across a style flush
function replay(el, cls) {
  el.classList.remove(cls);
  void el.offsetWidth;
  el.classList.add(cls);
}

function setLower(name, role) {
  const lower = $('.lower', hero);
  $('.nm', lower).textContent = name;
  $('.rl', lower).textContent = role;
  replay(lower, 'wipe');
}

function putMember() {
  $('[data-slot="member"]', heroIsl).replaceChildren($(`.card[data-who="${state.who}"] .mem`).cloneNode(true));
  const key = CAST[state.who][2];
  $$('.g-idle', heroIsl).forEach((g) => { g.className = g.className.replace(/\bpal-\w+/, `pal-${key}`); });
}
// the dancer wears the album playing
function putDancer() {
  const dn = $(`.card[data-dancer="${state.dancer}"] .dn`).cloneNode(true);
  const key = ALBUMS[state.album][0];
  dn.classList.replace('pal-teal', `pal-${key}`);
  if (state.album) $$('[filter]', dn).forEach((f) => f.setAttribute('filter', f.getAttribute('filter').replace(')', `-${key})`)));
  $('[data-slot="dancer"]', heroIsl).replaceChildren(dn);
  // the three take 60 pt wings, a solo 48 pt, as the app sizes them
  heroIsl.dataset.dance = state.dancer === 'three' ? 'trio' : 'solo';
}

function labelFor(scene) {
  if (scene === 'idle') return `${CAST[state.who][0]} idling beside the camera over a glow`;
  if (scene === 'music') return `${DANCERS[state.dancer][0]} dancing in the right wing while music plays`;
  return 'Claude on the left wing and Codex on the right, both working';
}

// pressed: each scene's pick. On camera: the one the demo is showing now.
function markCards() {
  for (const card of cards) {
    const picked = card.dataset.who ? card.dataset.who === state.who : card.dataset.dancer === state.dancer;
    card.setAttribute('aria-pressed', String(picked));
    card.classList.toggle('on', picked && (card.dataset.who ? state.scene === 'idle' : state.scene === 'music'));
  }
}

function renderHero(snap = true) {
  const s = state.scene;
  hero.classList.remove('boot');
  heroIsl.dataset.scene = s;
  $$(`.s-${s}`, heroIsl).forEach((slot) => replay(slot, 'enter'));
  if (s === 'idle') setLower(CAST[state.who][0], CAST[state.who][1]);
  else if (s === 'music') setLower(DANCERS[state.dancer][0], DANCERS[state.dancer][1]);
  else setLower('Claude Code & Codex', 'Sharing a desk. One wing each.');
  hero.setAttribute('aria-label', `Live demo of the notch: ${labelFor(s)}`);
  $$('[data-scene-btn]').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.sceneBtn === s)));
  markCards();
  // the one snap-zoom: only when entering the music scene with motion running
  heroShot.classList.remove('snap');
  if (s === 'music' && snap && !state.paused && !reduce.matches) replay(heroShot, 'snap');
}

// ---------- the 5 s scene cycle: stops on Pause, off-screen, in a hidden tab, or while a moment shows ----------
let timer = 0;
function running() { return !state.paused && state.onScreen && state.tabVisible && !state.kind; }
function schedule() {
  clearTimeout(timer);
  if (running()) timer = setTimeout(advance, SCENE_MS);
}
function advance() {
  state.scene = SCENES[(SCENES.indexOf(state.scene) + 1) % SCENES.length];
  renderHero();
  schedule();
}
function go(scene, snap = true) {
  dismiss();
  state.scene = scene;
  renderHero(snap);
  schedule();
}

function setPaused(paused) {
  state.paused = paused;
  root.classList.toggle('paused', paused);
  const word = paused ? 'Play' : 'Pause';
  for (const b of $$('[data-action="pause"]')) {
    const label = $('[data-label]', b);
    if (label) label.textContent = word;
    else b.setAttribute('aria-label', `${word} all motion`);
  }
  if (paused) heroShot.classList.remove('snap');
  schedule();
}

$$('[data-action="pause"]').forEach((b) => b.addEventListener('click', () => setPaused(!state.paused)));
$$('[data-scene-btn]').forEach((b) => b.addEventListener('click', () => go(b.dataset.sceneBtn)));

// a pick auditions in the hero's notch; bring the stage into view when any of it is off screen
function showHero() {
  const r = hero.getBoundingClientRect();
  if (r.top < 0 || r.bottom > innerHeight) hero.scrollIntoView({ block: 'nearest', behavior: reduce.matches ? 'auto' : 'smooth' });
}
for (const card of cards) {
  card.addEventListener('click', () => {
    if (card.dataset.who) {
      state.who = card.dataset.who;
      putMember();
      go('idle');
    } else {
      state.dancer = card.dataset.dancer;
      putDancer();
      go('music');
    }
    showHero();
  });
}

// off-screen regions rest (their loops pause); the hero also stops its cycle
const watch = new IntersectionObserver((entries) => {
  for (const e of entries) {
    e.target.classList.toggle('rest', !e.isIntersecting);
    if (e.target === hero) { state.onScreen = e.isIntersecting; schedule(); }
  }
});
[hero, $('.castgrid'), $('[data-notices]')].forEach((el) => el && watch.observe(el));
document.addEventListener('visibilitychange', () => { state.tabVisible = !document.hidden; schedule(); });
reduce.addEventListener('change', () => { if (reduce.matches) setPaused(true); });

// ---------- copy buttons, announced through a polite live region ----------
const status = $('[data-copy-status]');
function announce(msg) {
  status.textContent = '';
  setTimeout(() => { status.textContent = msg; }, 60);
}
function selectText(el) {
  const range = document.createRange();
  range.selectNodeContents(el);
  const sel = getSelection();
  sel.removeAllRanges();
  sel.addRange(range);
}
$$('[data-copy]').forEach((btn) => btn.addEventListener('click', async () => {
  const src = document.getElementById(btn.dataset.copy);
  const text = src.textContent.trim();
  try {
    await navigator.clipboard.writeText(text);
    btn.textContent = 'Copied';
    btn.classList.add('done');
    announce(`${btn.dataset.copyName} copied to the clipboard.`);
    setTimeout(() => { btn.textContent = 'Copy'; btn.classList.remove('done'); }, 1800);
  } catch (err) {
    console.warn('clipboard unavailable, selecting the text instead', err);
    selectText(src);
    announce('Copying is blocked here. The text is selected: press Command and C to copy it.');
  }
}));

// ---------- the playground: the app's moments, played in the hero's notch ----------
// Each is a strip from "What it does", cloned over the island: the prop punches in, then the title (0.1 s), the reading
// (0.2 s) and the caption (0.32 s), as the app times them; it leaves after 2.5 s. Pressing again only updates it,
// so the island never jumps. Paused or under Reduce Motion: fades only.
const SETTLE = 'cubic-bezier(.16, 1, .3, 1)';
const EVEN = 'cubic-bezier(.4, 0, .2, 1)';
const calm = () => state.paused || reduce.matches;
const notch = $('.notch', heroIsl);
const layer = document.createElement('div');
const strips = {};
for (const kind of ['charge', 'vol', 'copy', 'finish']) {
  strips[kind] = $(`.notices .s-${kind}`).cloneNode(true);
  // the originals keep the gradients and clips the copies point at
  $$('defs', strips[kind]).forEach((d) => d.remove());
}
layer.append(...Object.values(strips));
$('.minibox', strips.vol).insertAdjacentHTML('beforeend', '<g class="mute"><path d="M3.4 2L18.6 12.2"/><path d="M3.4 2L18.6 12.2"/></g>');
const vu = $$('.vu i', strips.vol);

// the dancers' keyline filters again in each album's glows
function addFilters() {
  for (const [key, , , glows] of ALBUMS.slice(1)) {
    glows.forEach((c, i) => {
      const f = $(`#dn-g${i}`).cloneNode(true);
      f.id = `dn-g${i}-${key}`;
      $('feFlood', f).setAttribute('flood-color', c);
      $('svg.defs').append(f);
    });
  }
}

// the notices wear the album playing; the meter mixes in sRGB, as the app does
const hex = (h, i) => parseInt(h.slice(1 + i * 2, 3 + i * 2), 16);
const mix = (a, b, t) => `rgb(${[0, 1, 2].map((i) => Math.round(hex(a, i) + (hex(b, i) - hex(a, i)) * t))})`;
function paintNotices() {
  const [key, right, marks] = ALBUMS[state.album];
  layer.className = `onair pal-${key}`;
  for (const strip of [strips.charge, strips.vol, strips.copy]) {
    $('.sg.l', strip).className = `sg l g-${key}`;
    $('.sg.r', strip).className = `sg r g-${right}`;
  }
  vu.forEach((v, i) => {
    const lo = Math.min(1, Math.floor(i / 3));
    v.style.setProperty('--c', i > 6 ? '#C0392B' : mix(marks[lo], marks[lo + 1], i / 3 - lo));
  });
}

// the widest strip fits the screen; read after layout
function fitNotices() {
  const fit = parseFloat(layer.style.getPropertyValue('--fit')) || 1;
  const z = parseFloat(getComputedStyle(hero).getPropertyValue('--z')) || 1;
  const pt = heroIsl.getBoundingClientRect().height / 32;
  const widest = Math.max(...Object.values(strips).map((s) => s.getBoundingClientRect().width)) / fit / pt + 12;
  layer.style.setProperty('--fit', Math.min(1, ($('.screen', hero).clientWidth - 20) / z / widest).toFixed(3));
}

let said = 0;
function say(msg, wait = 0) {
  clearTimeout(said);
  said = setTimeout(announce, wait, msg);
}

const fadeIn = (el, ms = 160) => el.animate({ opacity: [0, 1] }, { duration: ms, easing: 'ease-out' });
const rise = (els, delay) => els.forEach((el) => el.animate([{ opacity: 0, transform: 'translateY(4px)' }, { opacity: 1, transform: 'none' }],
  { duration: 450, delay, easing: SETTLE, fill: 'backwards' }));
const halt = (el) => el.getAnimations({ subtree: true }).forEach((a) => a.cancel());
const glint = (strip, delay) => $('.bolt', strip).animate({ transform: ['none', 'scale(1.18)', 'none'] }, { duration: 360, delay, easing: 'ease-out' });

let hold = 0;
let veil = null;
let stack = 1;
function leave(kind, ms) {
  const strip = strips[kind];
  strip.animate({ opacity: [1, 0] }, { duration: ms, easing: EVEN, fill: 'forwards' }).onfinish = () => {
    if (state.kind !== kind) { strip.classList.remove('on'); halt(strip); }
  };
}
// shows a moment and restarts its 2.5 s; true when it was showing already
function moment(kind) {
  clearTimeout(hold);
  hold = setTimeout(dismiss, HOLD_MS);
  if (state.kind === kind) return true;
  const was = state.kind;
  const strip = strips[kind];
  const quiet = calm();
  state.kind = kind;
  schedule();
  heroShot.classList.remove('snap');
  halt(strip);
  strip.style.zIndex = ++stack;
  strip.classList.add('on');
  if (was) leave(was, 200);
  else {
    veil?.cancel();
    veil = notch.animate({ opacity: [1, 0] }, { duration: 200, delay: quiet ? 140 : 60, fill: 'forwards' });
  }
  if (quiet) {
    fadeIn(strip, 200);
    return false;
  }
  const prop = $('.w.l', strip).firstElementChild;
  fadeIn(strip);
  strip.animate({ transform: ['scale(.92, .9)', 'none'] }, { duration: 450, easing: SETTLE });
  $$('.sg', strip).forEach((g) => fadeIn(g, 800));
  fadeIn(prop);
  prop.animate({ transform: ['scale(.6)', 'none'] }, { duration: 520, easing: 'cubic-bezier(.3, 1.55, .5, 1)' });
  rise([$('.t1', strip)], 100);
  rise($$('.w.r > *', strip), 200);
  rise([$('.cap', strip)], 320);
  return false;
}
function dismiss() {
  clearTimeout(hold);
  const kind = state.kind;
  if (!kind) return;
  const quiet = calm();
  state.kind = '';
  veil?.cancel();
  veil = notch.animate({ opacity: [0, 1] }, { duration: quiet ? 200 : 300, easing: EVEN });
  leave(kind, quiet ? 200 : 350);
  if (!quiet) $$(`.s-${state.scene}`, heroIsl).forEach((slot) => replay(slot, 'enter'));
  schedule();
}

// the copier: one scan sweeps the glass, then the sheet slides out
function runCopier(el) {
  $('.scan', el).animate([{ opacity: 0, transform: 'translateX(0)' }, { opacity: 1, offset: 0.15 }, { opacity: 1, offset: 0.85 }, { opacity: 0, transform: 'translateX(15px)' }],
    { duration: 700, easing: 'cubic-bezier(.45, 0, .55, 1)' });
  $('.sheet', el).animate([{ transform: 'translateY(-6.4px)' }, { transform: 'none' }], { duration: 480, delay: 620, easing: SETTLE, fill: 'backwards' });
}
// the agent finished: one small burst of confetti from the gold ring
function burst(el) {
  const bits = $$('.confetti i', el);
  bits.forEach((bit, i) => {
    const a = (i / bits.length) * Math.PI * 2 - Math.PI / 2 + (i % 2 ? 0.25 : -0.1);
    const d = 13 + (i % 3) * 4;
    const x = Math.cos(a) * d;
    const y = Math.sin(a) * d;
    bit.animate([
      { opacity: 1, transform: 'translate(0, 0) rotate(0deg) scale(.6)' },
      { opacity: 1, offset: 0.55, transform: `translate(${x * 0.8}px, ${y * 0.8}px) rotate(${i * 70}deg)` },
      { opacity: 0, transform: `translate(${x}px, ${y + 6}px) rotate(${i * 120}deg)` },
    ], { duration: 1100, delay: 120 + (i % 4) * 30, easing: SETTLE });
  });
}

// charging: a pour, the coffee rising to 64% (11.4 pt window, 4.1 pt left empty), the bolt's glint; again, just the glint
function charge() {
  const strip = strips.charge;
  if (moment('charge')) { if (!calm()) glint(strip, 0); }
  else if (!calm()) {
    $('.stream', strip).animate([{ opacity: 0, transform: 'scaleY(0)' }, { opacity: 1, transform: 'none', offset: 0.14 }, { opacity: 1, offset: 0.8 }, { opacity: 0, transform: 'translateY(8px)' }],
      { duration: 1120, delay: 300 });
    $('.lvl', strip).animate({ transform: ['translateY(11.4px)', 'translateY(4.1px)'] }, { duration: 800, delay: 420, easing: SETTLE, fill: 'backwards' });
    glint(strip, 1450);
  }
  say('Charging 64%');
}

// the volume, in sixteenths: the cones swell with the level and kick on a press (presses inside a kick are absorbed),
// the meter lights ceil(level x 9), and the caption changes only with its band
let kicked = -1e4;
function volume(step) {
  const strip = strips.vol;
  const cap = $('.cap', strip);
  state.vol = Math.min(16, Math.max(0, state.vol + step));
  const pct = Math.round((state.vol / 16) * 100);
  const words = BANDS.find(([top]) => pct <= top)[1];
  const again = moment('vol');
  $('.t1', strip).textContent = `${pct}%`;
  if (cap.textContent !== words) {
    cap.textContent = words;
    if (again) fadeIn(cap, 200);
  }
  vu.forEach((v, i) => v.classList.toggle('on', i < Math.ceil((pct * 9) / 100)));
  strip.classList.toggle('muted', !pct);
  const size = 1 + 0.35 * (pct / 100);
  const kick = !calm() && performance.now() - kicked > 220;
  if (kick) kicked = performance.now();
  for (const cone of $$('.cone', strip)) {
    cone.style.transform = `scale(${size})`;
    if (kick) cone.animate({ transform: [`scale(${size})`, `scale(${size * 1.12})`, `scale(${size})`], offset: [0, 0.36, 1] }, { duration: 220, easing: 'ease-out' });
  }
  say(`Volume ${pct}%`, 400);
}

// next song: the next album cross-fades in on the aurora, the cover chip changes and a new number starts
function nextSong() {
  const fades = state.scene !== 'music' ? [] : $$('.g-music:not(.fx)', heroIsl).map((g) => {
    const old = g.cloneNode();
    old.classList.add('fx');
    g.after(old);
    return old;
  });
  state.album = (state.album + 1) % ALBUMS.length;
  state.dancer = DANCES[(DANCES.indexOf(state.dancer) + 1) % DANCES.length];
  const key = ALBUMS[state.album][0];
  $$('.g-music:not(.fx), .s-music', heroIsl).forEach((el) => { el.className = el.className.replace(/\bpal-\w+/, `pal-${key}`); });
  putDancer();
  paintNotices();
  fades.forEach((old) => { old.animate({ opacity: [1, 0] }, { duration: calm() ? 200 : 900, easing: EVEN, fill: 'forwards' }).onfinish = () => old.remove(); });
  go('music', !fades.length);
  say(`Next song, ${key} cover. ${DANCERS[state.dancer][0]} dancing.`);
}

const PLAY = {
  song: nextSong,
  down: () => volume(-1),
  up: () => volume(1),
  charge,
  copy() {
    moment('copy');
    if (!calm()) runCopier(strips.copy);
    say('Copied text');
  },
  finish() {
    moment('finish');
    if (!calm()) burst(strips.finish);
    say('Claude finished in 1 minute 34 seconds, $4.12');
  },
};
$$('[data-play]').forEach((b) => b.addEventListener('click', () => PLAY[b.dataset.play]()));

// ---------- one-shot moments, never under Reduce Motion: the deal, the copier and the confetti (native), the charger (anime.js, loaded on approach) ----------
let anime = null;
function loadAnime() {
  anime ??= import('animejs');
  return anime;
}
// true while el is still wholly below the fold, so hiding it to play an entrance cannot flash
const below = (el) => el.getBoundingClientRect().top > innerHeight;

function onEnter(el, fn) {
  const io = new IntersectionObserver((entries) => {
    if (entries.some((e) => e.isIntersecting)) { io.disconnect(); fn(); }
  }, { threshold: 0.25 });
  io.observe(el);
}

// the dealt moment: the cast cards are dealt like a hand as they come into view. Native, so the
// cards right under the hero cost no library; it plays only while the grid is still below the fold.
function setupDeal() {
  const grid = $('.castgrid');
  if (!grid.animate || !below(grid)) return;
  cards.forEach((card) => { card.style.opacity = '0'; });
  onEnter(grid, () => cards.forEach((card, i) => {
    card.style.opacity = '';
    if (state.paused) return;
    card.animate([{ opacity: 0, transform: 'translateY(24px) rotate(-2.5deg)' }, { opacity: 1, transform: 'none' }],
      { duration: 640, delay: i * 55, easing: 'cubic-bezier(.16, 1, .3, 1)', fill: 'backwards' });
  }));
}

// the copier, as the playground runs it. Without motion the sheet is simply out.
function setupCopier() {
  const fig = $('[data-copier]');
  if (!fig || !below(fig)) return;
  const sheet = $('.sheet', fig);
  sheet.style.transform = 'translateY(-6.4px)';
  onEnter(fig, () => {
    sheet.style.transform = '';
    if (!state.paused) runCopier(fig);
  });
}

// the agent finished: the playground's burst, once, then nothing
function setupConfetti() {
  const fig = $('[data-finish]');
  if (fig && below(fig)) onEnter(fig, () => { if (!state.paused) burst(fig); });
}

// the charger moment: punch-in, pour, the level rises to the charge, the bolt glints.
// On SVG, anime.js reads x and y as attributes, so these moves name translateY.
function setupMoment({ createTimeline, utils, spring, stagger }) {
  const card = $('[data-moment]');
  if (!card || !below(card)) return;
  const punch = $('[data-m="punch"]', card);
  const words = $$('[data-m="word"]', card);
  const lvl = $('.lvl', card);
  const stream = $('.stream', card);
  const bolt = $('[data-m="bolt"]', card);
  // the mug's window is 11.4 pt tall; the charge shown is 64%
  const empty = 11.4;
  const full = empty * (1 - 0.64);
  utils.set(punch, { opacity: 0, scale: 0.9 });
  utils.set(words, { opacity: 0, translateY: 3 });
  utils.set(lvl, { translateY: empty });
  onEnter(card, () => {
    createTimeline({ defaults: { ease: 'outExpo' } })
      .add(punch, { opacity: [0, 1], duration: 130, ease: 'linear' }, 0)
      .add(punch, { scale: [0.9, 1], ease: spring({ bounce: 0.35, duration: 420 }) }, 0)
      .add(words, { opacity: [0, 1], translateY: [3, 0], duration: 370, delay: stagger(60) }, 80)
      .add(stream, { opacity: [0, 1], scaleY: [0, 1], duration: 160, ease: 'outQuad' }, 300)
      .add(lvl, { translateY: [empty, full], duration: 1000, ease: 'outCubic' }, 420)
      .add(stream, { opacity: [1, 0], translateY: [0, 8], duration: 220, ease: 'inQuad' }, 1200)
      .add(bolt, { scale: [1, 1.18, 1], duration: 360, ease: 'outQuad' }, 1450);
  });
}

// ---------- code blocks join the tab order only when they scroll sideways ----------
function markScrollers() {
  for (const el of $$(':is(pre, code)[data-label]')) {
    const scrolls = el.scrollWidth > el.clientWidth + 1;
    el.toggleAttribute('tabindex', scrolls);
    el.toggleAttribute('role', scrolls);
    el.toggleAttribute('aria-label', scrolls);
    if (scrolls) {
      el.tabIndex = 0;
      el.setAttribute('role', 'region');
      el.setAttribute('aria-label', el.dataset.label);
    }
  }
}
let resizeTimer = 0;
addEventListener('resize', () => {
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(markScrollers, 150);
});
document.fonts?.ready.then(markScrollers);

if (!reduce.matches && 'IntersectionObserver' in window) {
  setupDeal();
  setupCopier();
  setupConfetti();
  const mugFig = $('[data-moment]');
  const near = new IntersectionObserver((entries) => {
    if (!entries.some((e) => e.isIntersecting)) return;
    near.disconnect();
    loadAnime().then(setupMoment).catch((err) => console.warn('anime.js did not load; the page stays as it is', err));
  }, { rootMargin: '0px 0px 30% 0px' });
  if (mugFig) near.observe(mugFig);
}

// ---------- start: reads first, then the writes, so starting forces no extra layout ----------
markScrollers();
addFilters();
putDancer();
paintNotices();
heroIsl.append(layer);
new ResizeObserver(fitNotices).observe($('.screen', hero));
cards.forEach((card) => { card.disabled = false; });
root.classList.remove('static');
root.classList.add('ready');
setPaused(state.paused);
markCards();
// Pause is wired, so the looping demos may start
root.classList.add('live');
