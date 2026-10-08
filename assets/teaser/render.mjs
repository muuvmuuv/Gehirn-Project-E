// Renders scene.html in Playwright's cached headless Chromium and pipes the frames into ffmpeg.
//   node render.mjs <x|reel> stills <t,t,...> <dir>   one PNG per time
//   node render.mjs <x|reel> video <out.mp4>          the whole cut
import { chromium } from 'playwright-core';
import { spawn } from 'node:child_process';
import { mkdirSync, readdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const dir = fileURLToPath(new URL('.', import.meta.url));
const [cut, mode, a, b] = process.argv.slice(2);

// ponytail: macOS arm64 cache layout only
const cache = `${homedir()}/Library/Caches/ms-playwright`;
const shell = readdirSync(cache).filter((d) => d.startsWith('chromium_headless_shell-'))
  .sort((x, y) => x.split('-')[1] - y.split('-')[1]).at(-1);
const browser = await chromium.launch({
  executablePath: `${cache}/${shell}/chrome-headless-shell-mac-arm64/chrome-headless-shell`,
});
const page = await browser.newPage();
await page.goto(`file://${dir}scene.html?cut=${cut}`);
const { width, height, fps, duration } = await page.evaluate(async () => {
  await document.fonts.ready;
  await Promise.all([...document.images].filter((i) => i.src).map((i) => i.decode()));
  return window.SCENE;
});
await page.setViewportSize({ width, height });
const frame = async (t, opts) => {
  await page.evaluate((t) => window.render(t), t);
  return page.screenshot(opts);
};

if (mode === 'stills') {
  mkdirSync(b, { recursive: true });
  for (const t of a.split(',')) await frame(Number(t), { path: `${b}/${cut}-${t}.png` });
} else {
  const ff = spawn('ffmpeg', [
    '-y', '-loglevel', 'warning',
    '-f', 'image2pipe', '-framerate', String(fps), '-i', '-',
    // Buffer asks for an AAC track on X and Instagram alike and may refuse a video without one.
    '-f', 'lavfi', '-t', String(duration), '-i', 'anullsrc=r=48000:cl=stereo',
    // ffmpeg tags the colors from the frames, not from -color_primaries, so setparams sets them.
    '-vf', 'scale=out_color_matrix=bt709:out_range=tv,format=yuv420p,' +
      'setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv',
    '-c:v', 'libx264', '-profile:v', 'high', '-preset', 'slow', '-crf', '18', '-r', String(fps),
    '-c:a', 'aac', '-b:a', '128k', '-ar', '48000',
    // Meta's Reels spec allows no edit list and wants the moov atom first.
    '-use_editlist', '0', '-movflags', '+faststart+negative_cts_offsets', a,
  ], { stdio: ['pipe', 'inherit', 'inherit'] });
  for (let f = 0; f < Math.round(fps * duration); f++) {
    if (!ff.stdin.write(await frame(f / fps))) await new Promise((r) => ff.stdin.once('drain', r));
  }
  ff.stdin.end();
  await new Promise((r) => ff.on('close', r));
}
await browser.close();
