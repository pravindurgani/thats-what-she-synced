// That's What She Synced: the live notch demo, the cast picker, copy buttons and two one-shot moments.
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

const state = { scene: 'idle', who: 'scarn', dancer: 'three', paused: reduce.matches, onScreen: true, tabVisible: !document.hidden };

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
function putDancer() {
  $('[data-slot="dancer"]', heroIsl).replaceChildren($(`.card[data-dancer="${state.dancer}"] .dn`).cloneNode(true));
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

function renderHero() {
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
  if (s === 'music' && !state.paused && !reduce.matches) replay(heroShot, 'snap');
}

// ---------- the 5 s scene cycle: stops on Pause, off-screen, or in a hidden tab ----------
let timer = 0;
function running() { return !state.paused && state.onScreen && state.tabVisible; }
function schedule() {
  clearTimeout(timer);
  if (running()) timer = setTimeout(advance, SCENE_MS);
}
function advance() {
  state.scene = SCENES[(SCENES.indexOf(state.scene) + 1) % SCENES.length];
  renderHero();
  schedule();
}
function go(scene) {
  state.scene = scene;
  renderHero();
  schedule();
}

function setPaused(paused) {
  state.paused = paused;
  root.classList.toggle('paused', paused);
  $$('[data-action="pause"] [data-label]').forEach((l) => { l.textContent = paused ? 'Play' : 'Pause'; });
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

// ---------- two one-shot moments, never under Reduce Motion: the deal (native), the charger (anime.js, loaded on approach) ----------
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

// the charger moment: punch-in, pour, the level rises to the charge, the battery glints.
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
addEventListener('resize', () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(markScrollers, 150); });
document.fonts?.ready.then(markScrollers);

if (!reduce.matches && 'IntersectionObserver' in window) {
  setupDeal();
  const moment = $('[data-moment]');
  const near = new IntersectionObserver((entries) => {
    if (!entries.some((e) => e.isIntersecting)) return;
    near.disconnect();
    loadAnime().then(setupMoment).catch((err) => console.warn('anime.js did not load; the page stays as it is', err));
  }, { rootMargin: '0px 0px 30% 0px' });
  if (moment) near.observe(moment);
}

// ---------- start ----------
putDancer();
markScrollers();
cards.forEach((card) => { card.disabled = false; });
root.classList.remove('static');
root.classList.add('ready');
setPaused(state.paused);
markCards();
// Pause is wired, so the looping demos may start
root.classList.add('live');
