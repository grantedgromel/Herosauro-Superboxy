// Web QA driver: plays the exported HTML5 build the way a child would, in
// headless Chromium on SwiftShader WebGL2, and writes screenshots + a JSON log.
//
//   godot --headless --export-release "Web" /tmp/webqa/index.html   (from herosauro-superboxy/)
//   (cd /tmp/webqa && python3 -m http.server 8765 --bind 127.0.0.1) &
//   PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers NODE_PATH=/opt/node-tools/node_modules \
//     node tools/web_qa/play.mjs --url=http://127.0.0.1:8765/ --out=/tmp/webqa_shots [--only=desktop|touch]
//     [--nos3tc]  hide S3TC/BPTC/RGTC from WebGL, the way an iPad's Safari does
//     [--touchChapter=0|1|2] [--hold=20000] [--chapters=0,1,2]
//
// The canvas has no DOM, so every click is in canvas pixels. The game runs a
// 1280x720 base with stretch "expand"; the coordinates below are for the
// 1280x720 desktop viewport and the 1024x768 touch viewport and were read off
// the screenshots this script takes. Godot's main loop runs on
// requestAnimationFrame, so a long synchronous level build shows up as one long
// rAF gap: that gap is reported as the level-build time.
import { createRequire } from "module";
import fs from "fs";
import path from "path";

const require = createRequire(import.meta.url);
let pw;
try { pw = require("playwright"); } catch { pw = require("/opt/node-tools/node_modules/playwright"); }
const { chromium } = pw;

const args = Object.fromEntries(process.argv.slice(2).map((a) => {
  const m = a.match(/^--([^=]+)=?(.*)$/); return m ? [m[1], m[2] || "1"] : [a, "1"];
}));
const URL = args.url || "http://127.0.0.1:8765/";
const OUT = args.out || "/tmp/webqa_shots";
const ONLY = args.only || "";
const HOLD_MS = Number(args.hold || 20000);
fs.mkdirSync(OUT, { recursive: true });

const T0 = Date.now();
const report = { url: URL, started: new Date().toISOString(), runs: {} };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const t = () => ((Date.now() - T0) / 1000).toFixed(1);
function log(...a) { console.log(`[${t()}s]`, ...a); }

// Installed before any page script: rAF gap tracker and a hook that keeps the
// wasm memory so its size can be read later.
const INIT = (opt) => {
  const qa = (window.__qa = { frames: 0, last: 0, gaps: [], mem: null, firstFrame: 0 });
  if (opt && opt.noS3TC) {
    // Pretend to be an iPad: no S3TC/BPTC/RGTC desktop texture formats.
    const hide = (n) => /s3tc|bptc|rgtc/i.test(String(n));
    for (const C of [WebGLRenderingContext, WebGL2RenderingContext]) {
      const ge = C.prototype.getExtension, gs = C.prototype.getSupportedExtensions;
      C.prototype.getExtension = function (n) { return hide(n) ? null : ge.call(this, n); };
      C.prototype.getSupportedExtensions = function () { return (gs.call(this) || []).filter((n) => !hide(n)); };
    }
  }
  const tick = (ts) => {
    if (qa.last && ts - qa.last > 400) qa.gaps.push({ at: Math.round(ts), ms: Math.round(ts - qa.last) });
    qa.last = ts; qa.frames++;
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
  // Narration goes through the Web Speech API on web; record what it is asked to say.
  qa.speech = [];
  try {
    const ss = window.speechSynthesis;
    if (ss) {
      const sp = ss.speak.bind(ss);
      ss.speak = (u) => { qa.speech.push({ t: Math.round(performance.now()), lang: u.lang, voice: u.voice && u.voice.name, text: String(u.text).slice(0, 80) }); return sp(u); };
      qa.voices = () => ss.getVoices().map((v) => v.lang);
    } else qa.speech.push({ none: "no speechSynthesis" });
  } catch (e) { qa.speech.push({ err: String(e) }); }
  const grab = (res) => {
    try {
      const inst = res.instance || res;
      for (const v of Object.values(inst.exports || {})) if (v instanceof WebAssembly.Memory) qa.mem = v;
    } catch (e) {}
    return res;
  };
  const oi = WebAssembly.instantiate, os = WebAssembly.instantiateStreaming;
  WebAssembly.instantiate = function (...a) { return oi.apply(this, a).then(grab); };
  if (os) WebAssembly.instantiateStreaming = function (...a) { return os.apply(this, a).then(grab); };
  const OM = WebAssembly.Memory;
  WebAssembly.Memory = function (d) { const m = new OM(d); qa.mem = m; return m; };
  WebAssembly.Memory.prototype = OM.prototype;
};

async function stats(page, cdp) {
  const s = await page.evaluate(() => ({
    frames: window.__qa.frames, gaps: window.__qa.gaps.slice(),
    speechCalls: window.__qa.speech.length, speech: window.__qa.speech.slice(-4),
    voices: window.__qa.voices ? window.__qa.voices().length : 0,
    wasmMB: window.__qa.mem ? +(window.__qa.mem.buffer.byteLength / 1048576).toFixed(1) : null,
    jsHeapMB: performance.memory ? +(performance.memory.usedJSHeapSize / 1048576).toFixed(1) : null,
    now: performance.now(),
  }));
  if (cdp) {
    try {
      const m = await cdp.send("Performance.getMetrics");
      const g = (n) => (m.metrics.find((x) => x.name === n) || {}).value;
      s.cdpJsHeapMB = +((g("JSHeapUsedSize") || 0) / 1048576).toFixed(1);
    } catch {}
  }
  return s;
}

async function shot(page, run, name) {
  const p = path.join(OUT, `${run}_${name}.png`);
  try {
    await page.screenshot({ path: p, timeout: 60000 });
    const kb = Math.round(fs.statSync(p).size / 1024);
    log(`shot ${p} (${kb} KB)`);
    report.runs[run].shots.push({ name, path: p, kb, t: +t() });
    return kb;
  } catch (e) {
    log(`shot ${name} FAILED: ${e.message}`);
    report.runs[run].hangs.push(`screenshot ${name}: ${e.message}`);
    return 0;
  }
}

// Busy screens compress badly; the black loader / blank canvas compresses to a
// few KB. Poll until the canvas looks like a drawn frame.
async function waitDrawn(page, run, name, minKB, timeoutMs) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const p = path.join(OUT, `${run}_${name}_poll.png`);
    try { await page.screenshot({ path: p, timeout: 30000 }); } catch { await sleep(1000); continue; }
    const kb = fs.statSync(p).size / 1024;
    if (kb >= minKB) { fs.unlinkSync(p); return (Date.now() - start) / 1000; }
    await sleep(500);
  }
  report.runs[run].hangs.push(`${name}: canvas never looked drawn within ${timeoutMs / 1000}s`);
  return null;
}

// Wait for the rAF loop to settle after a build: returns the gaps that opened.
async function waitBuild(page, run, label, timeoutMs = 240000) {
  const before = (await page.evaluate(() => window.__qa.gaps.length));
  const start = Date.now();
  let quiet = 0, lastFrames = await page.evaluate(() => window.__qa.frames);
  while (Date.now() - start < timeoutMs) {
    await sleep(1000);
    let f;
    try { f = await page.evaluate(() => window.__qa.frames); } catch { continue; }
    // "settled" = frames are advancing for 4 consecutive seconds after at least 3 s
    // (SwiftShader runs the 3D levels at ~1 fps, so any advance counts)
    quiet = f > lastFrames ? quiet + 1 : 0;
    lastFrames = f;
    if (quiet >= 4 && Date.now() - start > 3000) break;
  }
  const gaps = await page.evaluate((b) => window.__qa.gaps.slice(b), before);
  const longest = gaps.reduce((a, g) => Math.max(a, g.ms), 0);
  const first = gaps.length ? gaps[0].ms : 0;
  const total = gaps.reduce((a, g) => a + g.ms, 0);
  const wall = (Date.now() - start) / 1000;
  if (wall * 1000 >= timeoutMs) report.runs[run].hangs.push(`${label}: frames did not settle in ${timeoutMs / 1000}s`);
  return { label, firstGaps: gaps.slice(0, 6).map((g) => g.ms), firstGapMs: first, longestGapMs: longest, sumGapsMs: total, gaps: gaps.length, settleWallS: +wall.toFixed(1) };
}

async function fps(page, ms) {
  const a = await page.evaluate(() => [window.__qa.frames, performance.now()]);
  await sleep(ms);
  const b = await page.evaluate(() => [window.__qa.frames, performance.now()]);
  return +(((b[0] - a[0]) * 1000) / (b[1] - a[1])).toFixed(1);
}

// Godot's web input listens on the canvas; Playwright mouse events land there.
async function click(page, x, y) { await page.mouse.click(x, y, { delay: 80 }); }
async function key(page, k, hold = 90) { await page.keyboard.down(k); await sleep(hold); await page.keyboard.up(k); }

async function touch(cdp, type, pts) {
  await cdp.send("Input.dispatchTouchEvent", { type, touchPoints: pts.map(([x, y], i) => ({ x, y, id: i + 1, radiusX: 8, radiusY: 8, force: 1 })) });
}
async function tap(cdp, x, y) { await touch(cdp, "touchStart", [[x, y]]); await sleep(90); await touch(cdp, "touchEnd", []); }
async function drag(cdp, x0, y0, x1, y1, holdMs) {
  await touch(cdp, "touchStart", [[x0, y0]]);
  const steps = 8;
  for (let i = 1; i <= steps; i++) { await touch(cdp, "touchMove", [[x0 + ((x1 - x0) * i) / steps, y0 + ((y1 - y0) * i) / steps]]); await sleep(40); }
  const end = Date.now() + holdMs;
  while (Date.now() < end) { await touch(cdp, "touchMove", [[x1 + (Math.random() - 0.5), y1]]); await sleep(150); }
  await touch(cdp, "touchEnd", []);
}

// ---------------------------------------------------------------------------
// Screen geometry (canvas px). Derived from bookshelf.gd/_layout,
// who_plays.gd/_layout, page_reader.gd/_layout and hud.gd, checked on shots.
function geo(w, h) {
  // bookshelf: 3 covers centred; centres at roughly 0.5w +/- (w_cover+gap)
  const top = 150, availH = h - top - 110;
  let ch = Math.max(300, Math.min(520, availH)), cw = ch * 0.74, gap = cw * 0.2;
  let total = cw * 3 + gap * 2;
  if (total > w - 96) { const k = (w - 96) / total; cw *= k; ch *= k; gap *= k; total *= k; }
  const x0 = (w - total) / 2, y0 = top + (availH - ch) / 2;
  const covers = [0, 1, 2].map((i) => [x0 + i * (cw + gap) + cw / 2, y0 + ch / 2]);
  return {
    covers,
    who: [[w / 2 - 220, h / 2], [w / 2 + 220, h / 2]],   // step 0: 1 player / 2 players; step 1: hero A / hero B
    skip: [w - 24 - 100, 24 + 42],
    pause: [24 + 50, 14 + 50],
    pauseBook: [w / 2, h / 2 + 95],
    stick: [w * 0.17, h * 0.72],
    attack: [w - 60, h - 60],   // touch overlay: BURST bottom-right, JUMP left of it, BOLT above it
  };
}

const CHAPTERS = ["adamastor", "dragao", "pandas"];

async function bootRun(browser, run, ctxOpts) {
  const R = (report.runs[run] = { console: [], errors: [], failedRequests: [], shots: [], hangs: [], timings: {}, builds: [], steps: [] });
  const ctx = await browser.newContext(ctxOpts);
  await ctx.addInitScript(INIT, { noS3TC: !!args.nos3tc });
  const page = await ctx.newPage();
  page.setDefaultTimeout(120000);
  page.on("console", (m) => { const line = `[${t()}s] ${m.type()}: ${m.text()}`; R.console.push(line); if (m.type() === "error" || m.type() === "warning") log(run, line); });
  page.on("pageerror", (e) => { R.errors.push(`[${t()}s] ${e.message}`); log(run, "PAGEERROR", e.message); });
  page.on("requestfailed", (q) => R.failedRequests.push(`${q.url()} ${q.failure()?.errorText}`));
  page.on("response", (r) => { if (r.status() >= 400) R.failedRequests.push(`${r.status()} ${r.url()}`); });
  page.on("crash", () => { R.hangs.push("PAGE CRASHED"); log(run, "PAGE CRASHED"); });
  const cdp = await ctx.newCDPSession(page);
  await cdp.send("Performance.enable").catch(() => {});
  const step = (s) => { R.steps.push(`[${t()}s] ${s}`); log(run, s); };

  const navStart = Date.now();
  step("goto");
  await page.goto(URL, { waitUntil: "load", timeout: 180000 });
  R.timings.htmlLoadS = (Date.now() - navStart) / 1000;
  // Godot's loader hides #status when the engine has started.
  try {
    await page.waitForFunction(() => { const s = document.getElementById("status"); return !s || getComputedStyle(s).display === "none" || s.style.visibility === "hidden"; }, null, { timeout: 300000, polling: 250 });
    R.timings.engineStartedS = (Date.now() - navStart) / 1000;
  } catch (e) { R.hangs.push("engine never started (#status still visible)"); }
  const drawn = await waitDrawn(page, run, "title", 60, 240000);
  R.timings.firstTitleFrameS = drawn == null ? null : +((Date.now() - navStart) / 1000).toFixed(1);
  step(`title drawn at ${R.timings.firstTitleFrameS}s`);
  await sleep(2500);
  R.timings.bootStats = await stats(page, cdp);
  return { ctx, page, cdp, R, step };
}

async function playChapter(env, run, i, mode, g) {
  const { page, cdp, R, step } = env;
  const id = CHAPTERS[i];
  const isTouch = mode === "touch";
  const press = async (pt) => (isTouch ? tap(cdp, pt[0], pt[1]) : click(page, pt[0], pt[1]));
  const useKeys = !isTouch && i % 2 === 0;  // adamastor + pandas by keyboard, dragao by mouse
  step(`chapter ${id} via ${isTouch ? "touch" : useKeys ? "keyboard" : "mouse"}`);
  await shot(page, run, `${id}_0_shelf`);
  if (useKeys) {
    // shelf focuses the suggested (next unfinished) cover; walk to the far left, then right i times.
    for (let k = 0; k < 3; k++) await key(page, "ArrowLeft");
    for (let k = 0; k < i; k++) await key(page, "ArrowRight");
    await sleep(400);
    await shot(page, run, `${id}_1_shelf_focused`);
    await key(page, "Enter");
  } else {
    await press(g.covers[i]);
  }
  await sleep(2500);
  await shot(page, run, `${id}_2_who`);
  if (useKeys) {
    // "1 jogador" already has focus. (ArrowLeft from it moves focus to the
    // Back arrow, so a child's Left+Enter returns to the shelf.)
    await key(page, "Enter");             // 1 player
    await sleep(2000);
    await shot(page, run, `${id}_3_hero`);
    await key(page, "Enter");             // default hero
  } else {
    await press(g.who[0]);
    await sleep(2000);
    await shot(page, run, `${id}_3_hero`);
    await press(g.who[0]);
  }
  await sleep(3000);
  await shot(page, run, `${id}_4_page1`);
  if (useKeys) {
    // Keyboard has no skip: page through like a child pressing space.
    await key(page, " "); await sleep(2500);
    await shot(page, run, `${id}_5_page2`);
    for (let k = 0; k < 12; k++) { await key(page, " "); await sleep(1200); }
  } else {
    await press(g.skip);
  }
  const fs0 = Date.now();
  step(`${id}: intro left, waiting for level`);
  const b = await waitBuild(page, run, id);
  b.fromSkipS = +((Date.now() - fs0) / 1000).toFixed(1);
  R.builds.push(b);
  step(`${id}: build ${JSON.stringify(b)}`);
  await sleep(1500);
  await shot(page, run, `${id}_6_level`);
  b.fpsIdle = await fps(page, 4000);

  // ~20 s of play
  const end = Date.now() + HOLD_MS;
  if (isTouch) {
    await shot(page, run, `${id}_7_touch_before_drag`);
    await drag(cdp, g.stick[0], g.stick[1], g.stick[0] + 90, g.stick[1] - 20, 5000);
    await shot(page, run, `${id}_8_touch_after_drag`);
    // jump is the easiest button to see working: the hero is in the air on the next shot
    await touch(cdp, "touchStart", [[g.attack[0] - 97, g.attack[1]]]); await sleep(400); await touch(cdp, "touchEnd", []);
    await sleep(300);
    await shot(page, run, `${id}_8b_touch_jump`);
    for (let k = 0; k < 6; k++) {
      await touch(cdp, "touchStart", [[g.attack[0], g.attack[1]]]); await sleep(350); await touch(cdp, "touchEnd", []);
      if (k === 0) await shot(page, run, `${id}_8c_touch_attack`);
      await sleep(500);
    }
    await drag(cdp, g.stick[0], g.stick[1], g.stick[0] - 90, g.stick[1] + 10, 4000);
  } else {
    const a = await page.evaluate(() => [window.__qa.frames, performance.now()]);
    const dirs = ["d", "w", "a", "s", "ArrowRight"];
    let d = 0;
    while (Date.now() < end) {
      const dk = dirs[d++ % dirs.length];
      await page.keyboard.down(dk);
      for (let k = 0; k < 4; k++) { await key(page, "j", 60); await sleep(250); }
      await key(page, " ", 120);
      await key(page, "k", 60);
      await sleep(400);
      await page.keyboard.up(dk);
    }
    const bb = await page.evaluate(() => [window.__qa.frames, performance.now()]);
    b.fpsPlaying = +(((bb[0] - a[0]) * 1000) / (bb[1] - a[1])).toFixed(1);
  }
  await shot(page, run, `${id}_9_after_play`);
  b.statsAfterPlay = await stats(page, cdp);

  // back to the book through pause
  if (isTouch) await tap(cdp, g.pause[0], g.pause[1]); else await key(page, "Escape");
  await sleep(1500);
  await shot(page, run, `${id}_A_pause`);
  if (isTouch || !useKeys) await press(g.pauseBook);
  else { await key(page, "ArrowDown"); await key(page, "ArrowDown"); await sleep(300); await key(page, "Enter"); }
  await sleep(4000);
  await shot(page, run, `${id}_B_after_book`);
}

async function main() {
  const browser = await chromium.launch({
    headless: true,
    args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--enable-webgl", "--use-gl=angle", "--autoplay-policy=user-gesture-required"],
  });
  report.browser = browser.version();
  const modes = [
    ["desktop", { viewport: { width: 1280, height: 720 } }],
    ["touch", { viewport: { width: 1024, height: 768 }, hasTouch: true, isMobile: true, deviceScaleFactor: 1 }],
  ].filter(([m]) => !ONLY || ONLY === m);
  for (const [mode, opts] of modes) {
    let env;
    try {
      env = await bootRun(browser, mode, opts);
      const vp = opts.viewport;
      const g = geo(vp.width, vp.height);
      env.R.webgl = await env.page.evaluate(() => { const c = document.createElement("canvas"); const gl = c.getContext("webgl2"); if (!gl) return "no webgl2"; const e = gl.getExtension("WEBGL_debug_renderer_info"); return e ? gl.getParameter(e.UNMASKED_RENDERER_WEBGL) : "webgl2"; });
      await shot(env.page, mode, "00_title");
      // continue past the title
      if (mode === "touch") await tap(env.cdp, vp.width / 2, vp.height / 2); else await key(env.page, "Enter");
      await sleep(2500);
      await shot(env.page, mode, "01_shelf");
      const list = mode === "touch" ? [Number(args.touchChapter || 1)] : (args.chapters || "0,1,2").split(",").map(Number);
      for (const i of list) {
        try { await playChapter(env, mode, i, mode, g); }
        catch (e) { env.R.hangs.push(`chapter ${CHAPTERS[i]}: ${e.message}`); log(mode, "chapter error", e.message); await shot(env.page, mode, `${CHAPTERS[i]}_ERR`); }
      }
      env.R.finalStats = await stats(env.page, env.cdp);
    } catch (e) {
      log(mode, "RUN ERROR", e.stack);
      if (report.runs[mode]) report.runs[mode].hangs.push(`run: ${e.message}`);
    } finally {
      if (env) await env.ctx.close().catch(() => {});
    }
  }
  await browser.close();
  report.totalS = +t();
  fs.writeFileSync(path.join(OUT, "report.json"), JSON.stringify(report, null, 1));
  log("wrote", path.join(OUT, "report.json"));
}

main().catch((e) => { console.error(e); process.exit(1); });
