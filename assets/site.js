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

const state = { scene: 'idle', who: 'scarn', dancer: 'three', last: 'cast', paused: reduce.matches, onScreen: true, tabVisible: !document.hidden };

const hero = $('[data-demo="hero"]');
const test = $('[data-demo="test"]');
if (!hero || !test) throw new Error('demo markup missing');
const heroIsl = $('.isl', hero);
const heroShot = $('.shot', hero);
const testIsl = $('.isl', test);

// restart a CSS animation by toggling its class across a style flush
function replay(el, cls) {
  el.classList.remove(cls);
  void el.offsetWidth;
  el.classList.add(cls);
}

function setLower(stage, name, role) {
  const lower = $('.lower', stage);
  $('.nm', lower).textContent = name;
  $('.rl', lower).textContent = role;
  replay(lower, 'wipe');
}

function cloneMember(id) {
  return $(`.crow[data-who="${id}"] .mem`).cloneNode(true);
}
function cloneDancer(id) {
  return $(`.crow[data-dancer="${id}"] .dn`).cloneNode(true);
}

function putMember(isl) {
  const slot = $('[data-slot="member"]', isl);
  slot.replaceChildren(cloneMember(state.who));
  const key = CAST[state.who][2];
  $$('.g-idle', isl).forEach((g) => { g.className = g.className.replace(/\bpal-\w+/, `pal-${key}`); });
}
function putDancer(isl) {
  $('[data-slot="dancer"]', isl).replaceChildren(cloneDancer(state.dancer));
}

function labelFor(scene) {
  if (scene === 'idle') return `${CAST[state.who][0]} idling beside the camera over a glow`;
  if (scene === 'music') return `${DANCERS[state.dancer][0]} dancing in the right wing while music plays`;
  return 'Claude on the left wing and Codex on the right, both working';
}

function renderHero() {
  const s = state.scene;
  hero.classList.remove('boot');
  heroIsl.dataset.scene = s;
  $$(`.s-${s}`, heroIsl).forEach((slot) => replay(slot, 'enter'));
  if (s === 'idle') setLower(hero, CAST[state.who][0], CAST[state.who][1]);
  else if (s === 'music') setLower(hero, DANCERS[state.dancer][0], DANCERS[state.dancer][1]);
  else setLower(hero, 'Claude Code & Codex', 'Sharing a desk. One wing each.');
  hero.setAttribute('aria-label', `Live demo of the notch: ${labelFor(s)}`);
  $$('[data-scene-btn]').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.sceneBtn === s)));
  // the one snap-zoom: only when entering the music scene with motion running
  heroShot.classList.remove('snap');
  if (s === 'music' && !state.paused && !reduce.matches) replay(heroShot, 'snap');
}

function renderTest() {
  const music = state.last === 'dancer';
  testIsl.dataset.scene = music ? 'music' : 'idle';
  $$(music ? '.s-music' : '.s-idle', testIsl).forEach((slot) => replay(slot, 'enter'));
  const [name, role] = music ? DANCERS[state.dancer] : CAST[state.who];
  setLower(test, name, role);
  const note = music ? `${name}, wearing a teal cover.` : `${name}, at rest.`;
  $('[data-test-note]').textContent = `Screen test. ${note}`;
  test.setAttribute('aria-label', `Screen test: ${note}`);
  $$('.crow').forEach((row) => {
    const on = music ? row.dataset.dancer === state.dancer : row.dataset.who === state.who;
    row.setAttribute('aria-pressed', String(on));
  });
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
// when the screen test is out of view (it stops being sticky on short screens), bring it back so a pick is seen
function showTest() {
  const r = test.getBoundingClientRect();
  if (r.top < 0 || r.bottom > innerHeight) {
    $('.screentest').scrollIntoView({ block: 'nearest', behavior: reduce.matches ? 'auto' : 'smooth' });
  }
}
$$('.crow[data-who]').forEach((row) => row.addEventListener('click', () => {
  state.who = row.dataset.who;
  state.last = 'cast';
  [heroIsl, testIsl].forEach(putMember);
  renderTest();
  go('idle');
  showTest();
}));
$$('.crow[data-dancer]').forEach((row) => row.addEventListener('click', () => {
  state.dancer = row.dataset.dancer;
  state.last = 'dancer';
  [heroIsl, testIsl].forEach(putDancer);
  renderTest();
  go('music');
  showTest();
}));

// off-screen regions rest (their loops pause); the hero also stops its cycle
const watch = new IntersectionObserver((entries) => {
  for (const e of entries) {
    e.target.classList.toggle('rest', !e.isIntersecting);
    if (e.target === hero) { state.onScreen = e.isIntersecting; schedule(); }
  }
});
[hero, $('.castgrid'), $('[data-moment]')].forEach((el) => el && watch.observe(el));
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

// ---------- one-shot motion with anime.js (loaded on approach, never under Reduce Motion) ----------
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

// the dealt moment: the call sheet is dealt like cards as it comes into view
function setupDeal({ animate, stagger, spring, utils }) {
  const list = $('.sheetlist');
  const rows = $$('.crow', list);
  if (!below(list)) return;
  utils.set(rows, { opacity: 0, x: -36, rotate: -2.5 });
  onEnter(list, () => {
    animate(rows, { opacity: [0, 1], x: [-36, 0], rotate: [-2.5, 0], delay: stagger(65), ease: spring({ bounce: 0.3, duration: 650 }) });
  });
}

// the charger moment: punch-in, pour, the level rises to the charge, a steam puff, the bolt glints
function setupMoment({ createTimeline, utils, spring, stagger }) {
  const card = $('[data-moment]');
  if (!card || !below(card)) return;
  const punch = $('[data-m="punch"]', card);
  const words = $$('[data-m="word"]', card);
  const lvl = $('.lvl', card);
  const stream = $('.stream', card);
  const steam = $$('.steam2 path', card);
  const bolt = $('.bolt', card);
  const full = 21 * (1 - 0.62);
  utils.set(punch, { opacity: 0, scale: 0.9 });
  utils.set(words, { opacity: 0, y: 3 });
  utils.set(lvl, { y: 21 });
  onEnter(card, () => {
    createTimeline({ defaults: { ease: 'outExpo' } })
      .add(punch, { opacity: [0, 1], duration: 130, ease: 'linear' }, 0)
      .add(punch, { scale: [0.9, 1], ease: spring({ bounce: 0.35, duration: 420 }) }, 0)
      .add(words, { opacity: [0, 1], y: [3, 0], duration: 370, delay: stagger(60) }, 80)
      .add(stream, { opacity: [0, 1], scaleY: [0, 1], duration: 160, ease: 'outQuad' }, 300)
      .add(lvl, { y: [21, full], duration: 1000, ease: 'outCubic' }, 420)
      .add(stream, { opacity: [1, 0], y: [0, 14], duration: 220, ease: 'inQuad' }, 1200)
      .add(steam, { opacity: [0, 0.95, 0], y: [3, 0, -4], duration: 600, delay: stagger(250), ease: 'outSine' }, 1450)
      .add(bolt, { scale: [1, 1.18, 1], duration: 360, ease: 'outQuad' }, 1450);
  });
}

// ---------- code blocks join the tab order only when they scroll sideways ----------
function markScrollers() {
  for (const el of $$('[data-label]')) {
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
  const near = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      near.unobserve(e.target);
      const setup = e.target.matches('.sheetlist') ? setupDeal : setupMoment;
      loadAnime().then(setup).catch((err) => console.warn('anime.js did not load; the page stays as it is', err));
    }
  }, { rootMargin: '0px 0px 60% 0px' });
  [$('.sheetlist'), $('[data-moment]')].forEach((el) => el && near.observe(el));
}

// ---------- start ----------
putDancer(testIsl);
markScrollers();
$$('.crow').forEach((row) => { row.disabled = false; });
root.classList.remove('static');
root.classList.add('ready');
setPaused(state.paused);
// Pause is wired, so the looping demos may start
root.classList.add('live');
