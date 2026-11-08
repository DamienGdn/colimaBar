// Renders the SVG sources in design/ into the PNG assets used by the app.
//
//   npm i -D playwright && npx playwright install chromium   (once)
//   node scripts/render-icons.mjs
//
// Outputs:
//   build/AppIcon.iconset/*.png   -> pack with `iconutil -c icns` (see `make icons`)
//                                    16/32 px use design/AppIcon-small.svg
//   Resources/colimabar.png       (22x22 menu bar template glyph)
//   Resources/colimabar@2x.png    (44x44)
//   docs/icon.png                 (256x256, README)
//   tauri/src-tauri/icons/*.png, icon.ico  (Linux / Windows app icons; icon.icns is copied by `make icons`)
//   tauri/src-tauri/icons/tray/*.png       (64x64 tray icons: running / transitioning / stopped)
import { chromium } from 'playwright';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const appSvg   = readFileSync(join(root, 'design/AppIcon.svg'), 'utf8');
// Simplified artwork (no strip / ribs / shadows) stays legible at 16-32 px.
const smallSvg = readFileSync(join(root, 'design/AppIcon-small.svg'), 'utf8');
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
  const svgFor = (px) => (px <= 32 ? smallSvg : appSvg);
  await render(svgFor(base),     base,     join(iconset, `icon_${base}x${base}.png`));
  await render(svgFor(base * 2), base * 2, join(iconset, `icon_${base}x${base}@2x.png`));
}
await render(appSvg, 256, join(root, 'docs/icon.png'));
await render(menuSvg, 22, join(root, 'Resources/colimabar.png'));
await render(menuSvg, 44, join(root, 'Resources/colimabar@2x.png'));

// Tauri (Linux / Windows) app icon source + tray icons.
// Tray icons use the colored small artwork so they read on light and dark
// panels alike, with the same status badge as the macOS menu bar glyph.
const tauriIcons = join(root, 'tauri/src-tauri/icons');
mkdirSync(join(tauriIcons, 'tray'), { recursive: true });
for (const [file, size] of [['32x32.png', 32], ['64x64.png', 64], ['128x128.png', 128],
                            ['128x128@2x.png', 256], ['icon.png', 512]]) {
  await render(size <= 32 ? smallSvg : appSvg, size, join(tauriIcons, file));
}

// Windows .ico with PNG entries (supported since Vista): small artwork for <= 48 px.
const icoSizes = [16, 24, 32, 48, 64, 128, 256];
const icoDir = join(root, 'build/ico');   // kept out of the .iconset (iconutil rejects extra files)
mkdirSync(icoDir, { recursive: true });
const pngs = [];
for (const size of icoSizes) {
  const out = join(icoDir, `${size}.png`);
  await render(size <= 48 ? smallSvg : appSvg, size, out);
  pngs.push(readFileSync(out));
}
const header = Buffer.alloc(6 + 16 * pngs.length);
header.writeUInt16LE(0, 0);            // reserved
header.writeUInt16LE(1, 2);            // type: icon
header.writeUInt16LE(pngs.length, 4);  // count
let offset = header.length;
pngs.forEach((png, i) => {
  const e = 6 + 16 * i, size = icoSizes[i];
  header.writeUInt8(size >= 256 ? 0 : size, e);      // width (0 = 256)
  header.writeUInt8(size >= 256 ? 0 : size, e + 1);  // height
  header.writeUInt16LE(1, e + 4);                    // color planes
  header.writeUInt16LE(32, e + 6);                   // bits per pixel
  header.writeUInt32LE(png.length, e + 8);
  header.writeUInt32LE(offset, e + 12);
  offset += png.length;
});
writeFileSync(join(tauriIcons, 'icon.ico'), Buffer.concat([header, ...pngs]));

const smallSrc = 'data:image/svg+xml;base64,' + Buffer.from(smallSvg).toString('base64');
const trayStates = {
  running:       { badge: '#30D158', dim: false },
  transitioning: { badge: '#FF9F0A', dim: false },
  stopped:       { badge: null,      dim: true  },
};
for (const [name, { badge, dim }] of Object.entries(trayStates)) {
  const size = 64;
  await page.setViewportSize({ width: size, height: size });
  await page.setContent(`<html><body style="margin:0;background:transparent">
    <div style="position:relative;width:${size}px;height:${size}px">
      <img src="${smallSrc}" width="${size}" height="${size}"
           style="display:block;${dim ? 'filter:grayscale(1);opacity:.6' : ''}">
      ${badge ? `<div style="position:absolute;right:1px;bottom:1px;width:24px;height:24px;border-radius:50%;
           background:${badge};box-shadow:0 0 0 4px #fff"></div>` : ''}
    </div></body></html>`);
  await page.waitForFunction(() => document.images[0].complete);
  await page.screenshot({ path: join(tauriIcons, 'tray', `${name}.png`), omitBackground: true,
                          clip: { x: 0, y: 0, width: size, height: size } });
}

await browser.close();
console.log('Icons rendered. Run `iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns` to pack.');
