// Renders the SVG sources in design/ into the PNG assets used by the app.
//
//   npm i -D playwright && npx playwright install chromium   (once)
//   node scripts/render-icons.mjs
//
// Outputs:
//   build/AppIcon.iconset/*.png   -> pack with `iconutil -c icns` (see `make icons`)
//   Resources/colimabar.png       (22x22 menu bar template glyph)
//   Resources/colimabar@2x.png    (44x44)
//   docs/icon.png                 (256x256, README)
import { chromium } from 'playwright';
import { readFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const appSvg  = readFileSync(join(root, 'design/AppIcon.svg'), 'utf8');
const menuSvg = readFileSync(join(root, 'design/MenuBarIcon.svg'), 'utf8');

const iconset = join(root, 'build/AppIcon.iconset');
mkdirSync(iconset, { recursive: true });

const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 1 });

async function render(svg, size, out) {
  await page.setViewportSize({ width: size, height: size });
  const src = 'data:image/svg+xml;base64,' + Buffer.from(svg).toString('base64');
  await page.setContent(
    `<html><body style="margin:0;background:transparent">` +
    `<img src="${src}" width="${size}" height="${size}" style="display:block"></body></html>`);
  await page.waitForFunction(() => document.images[0].complete);
  await page.screenshot({ path: out, omitBackground: true, clip: { x: 0, y: 0, width: size, height: size } });
}

for (const base of [16, 32, 128, 256, 512]) {
  await render(appSvg, base,     join(iconset, `icon_${base}x${base}.png`));
  await render(appSvg, base * 2, join(iconset, `icon_${base}x${base}@2x.png`));
}
await render(appSvg, 256, join(root, 'docs/icon.png'));
await render(menuSvg, 22, join(root, 'Resources/colimabar.png'));
await render(menuSvg, 44, join(root, 'Resources/colimabar@2x.png'));

await browser.close();
console.log('Icons rendered. Run `iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns` to pack.');
