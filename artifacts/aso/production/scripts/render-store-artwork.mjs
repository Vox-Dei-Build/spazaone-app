import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { dirname, extname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const root = resolve(scriptDir, '../../../..');
const productionRoot = resolve(root, 'artifacts/aso/production');
const rawRoot = resolve(root, 'artifacts/aso/raw');
const python = '/Users/admin/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3';
const pythonPath = '/Users/admin/.cache/codex-runtimes/codex-primary-runtime/dependencies/python';
const playwrightRoot = '/Users/admin/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/.pnpm/playwright@1.61.1/node_modules/playwright';
const headlessShell = '/Users/admin/Library/Caches/ms-playwright/chromium_headless_shell-1181/chrome-mac/headless_shell';
const require = createRequire(import.meta.url);
const { chromium } = require(playwrightRoot);

if (!existsSync(headlessShell)) {
  throw new Error(`The bundled Chromium headless shell was not found at ${headlessShell}`);
}

const assetRoot = resolve(productionRoot, 'assets');
const fontRoot = resolve(productionRoot, 'fonts');
const cartPath = resolve(assetRoot, 'spazaone-cart.png');
const originalFeaturePath = resolve(assetRoot, 'original-feature-graphic.png');
const poppinsRegularPath = resolve(fontRoot, 'poppins-regular.ttf');
const poppinsBoldPath = resolve(fontRoot, 'poppins-bold.ttf');
const poppinsExtraBoldPath = resolve(fontRoot, 'poppins-extrabold.ttf');
const poppinsExtraBoldItalicPath = resolve(fontRoot, 'poppins-extrabold-italic.ttf');

for (const file of [
  cartPath,
  originalFeaturePath,
  poppinsRegularPath,
  poppinsBoldPath,
  poppinsExtraBoldPath,
  poppinsExtraBoldItalicPath,
]) {
  if (!existsSync(file)) throw new Error(`Missing artwork dependency: ${file}`);
}

const colours = {
  navy: '#201D31',
  yellow: '#FFC629',
  ink: '#1E1A2A',
  paper: '#FBFAF8',
  white: '#FFFFFF',
  muted: '#6C6875',
  green: '#1D913F',
};

const slides = [
  {
    slug: '01-your-whole-shop',
    headline: ['Your whole shop,', 'in your pocket.'],
    body: ['Orders, balances, stock and sales—', 'together in one simple app.'],
    source: resolve(rawRoot, 'ios/01-login.png'),
  },
  {
    slug: '02-customer-balances',
    headline: ['Keep customer', 'balances clear.'],
    body: ['Track what is owed, what was paid', 'and what still needs following up.'],
    source: resolve(rawRoot, 'android/03-customer-pay-later-sanitized.png'),
  },
  {
    slug: '03-products-and-stock',
    headline: ['Track products', 'and stock.'],
    body: ['Keep prices, availability and stock', 'counts together in one place.'],
    source: resolve(rawRoot, 'android/02-products.png'),
  },
  {
    slug: '04-sales-and-profit',
    headline: ['See sales and profit,', 'at a glance.'],
    body: ['Know how the business is moving', 'without waiting for month-end.'],
    source: resolve(rawRoot, 'android/04-sales.png'),
  },
  {
    slug: '05-whatsapp-marketing',
    headline: ['Bring customers back', 'on WhatsApp.'],
    body: ['Create promotions and keep customer', 'follow-ups organised.'],
    source: resolve(rawRoot, 'android/05-marketing.png'),
  },
  {
    slug: '06-message-templates',
    headline: ['Keep messages', 'ready to send.'],
    body: ['Save WhatsApp and SMS templates', 'for the messages you send often.'],
    source: resolve(rawRoot, 'android/06-templates.png'),
  },
];

for (const slide of slides) {
  if (!existsSync(slide.source)) throw new Error(`Missing screenshot source: ${slide.source}`);
}

const mimeType = (file) => {
  const extension = extname(file).toLowerCase();
  if (extension === '.jpg' || extension === '.jpeg') return 'image/jpeg';
  if (extension === '.ttf') return 'font/ttf';
  return 'image/png';
};

const dataUri = (file) => `data:${mimeType(file)};base64,${readFileSync(file).toString('base64')}`;

const fontData = {
  regular: readFileSync(poppinsRegularPath).toString('base64'),
  bold: readFileSync(poppinsBoldPath).toString('base64'),
  extraBold: readFileSync(poppinsExtraBoldPath).toString('base64'),
  extraBoldItalic: readFileSync(poppinsExtraBoldItalicPath).toString('base64'),
};
const cartData = dataUri(cartPath);
const originalFeatureData = dataUri(originalFeaturePath);

const fontStyles = `
  @font-face { font-family: 'Poppins'; src: url(data:font/ttf;base64,${fontData.regular}) format('truetype'); font-weight: 400; font-style: normal; }
  @font-face { font-family: 'Poppins'; src: url(data:font/ttf;base64,${fontData.bold}) format('truetype'); font-weight: 700; font-style: normal; }
  @font-face { font-family: 'Poppins'; src: url(data:font/ttf;base64,${fontData.extraBold}) format('truetype'); font-weight: 800; font-style: normal; }
  @font-face { font-family: 'Poppins'; src: url(data:font/ttf;base64,${fontData.extraBoldItalic}) format('truetype'); font-weight: 800; font-style: italic; }
  .brand { font-family: 'Poppins', sans-serif; font-weight: 800; font-style: italic; }
  .display { font-family: 'Poppins', sans-serif; font-weight: 800; }
  .body { font-family: 'Poppins', sans-serif; font-weight: 400; }
  .label { font-family: 'Poppins', sans-serif; font-weight: 700; }
`;

function brandLockup({ x, y, colour, scale = 1, centered = false }) {
  const width = 420 * scale;
  const transform = centered ? `translate(${x - width / 2} ${y})` : `translate(${x} ${y})`;
  return `
    <g transform="${transform}">
      <image href="${cartData}" x="0" y="0" width="82" height="82" transform="scale(${scale})" />
      <text x="98" y="65" class="brand" font-size="62" fill="${colour}" letter-spacing="-2" transform="scale(${scale})">SpazaOne</text>
    </g>`;
}

function sharedDefs(id) {
  return `
    <defs>
      <style>${fontStyles}</style>
      <filter id="phone-shadow-${id}" x="-30%" y="-20%" width="160%" height="160%">
        <feDropShadow dx="0" dy="34" stdDeviation="34" flood-color="#090712" flood-opacity="0.34" />
      </filter>
      <filter id="ambient-${id}" x="-60%" y="-60%" width="220%" height="220%">
        <feGaussianBlur stdDeviation="92" />
      </filter>
      <linearGradient id="steel-${id}" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0" stop-color="#171717" />
        <stop offset="0.08" stop-color="#484848" />
        <stop offset="0.16" stop-color="#111111" />
        <stop offset="0.84" stop-color="#111111" />
        <stop offset="0.92" stop-color="#4B4B4B" />
        <stop offset="1" stop-color="#171717" />
      </linearGradient>
    </defs>`;
}

function phoneMockup({ x, y, width, height, source, id, platform }) {
  const apple = platform === 'app-store';
  const frame = apple ? 18 : 16;
  const radius = apple ? Math.round(width * 0.12) : Math.round(width * 0.09);
  const innerRadius = radius - frame;
  const innerX = x + frame;
  const innerY = y + frame;
  const innerWidth = width - frame * 2;
  const innerHeight = height - frame * 2;
  const image = dataUri(source);
  return `
    <g filter="url(#phone-shadow-${id})">
      <rect x="${x - 8}" y="${y + height * 0.17}" width="10" height="${height * 0.1}" rx="5" fill="#171717" />
      <rect x="${x - 8}" y="${y + height * 0.30}" width="10" height="${height * 0.17}" rx="5" fill="#171717" />
      <rect x="${x + width - 2}" y="${y + height * 0.28}" width="10" height="${height * 0.18}" rx="5" fill="#171717" />
      <rect x="${x}" y="${y}" width="${width}" height="${height}" rx="${radius}" fill="url(#steel-${id})" />
      <rect x="${x + 7}" y="${y + 7}" width="${width - 14}" height="${height - 14}" rx="${radius - 7}" fill="#090909" stroke="#5C5C5C" stroke-width="3" />
      <clipPath id="screen-${id}">
        <rect x="${innerX}" y="${innerY}" width="${innerWidth}" height="${innerHeight}" rx="${innerRadius}" />
      </clipPath>
      <g clip-path="url(#screen-${id})">
        <rect x="${innerX}" y="${innerY}" width="${innerWidth}" height="${innerHeight}" fill="#FFFFFF" />
        <image href="${image}" x="${innerX}" y="${innerY}" width="${innerWidth}" height="${innerHeight}" preserveAspectRatio="xMidYMin slice" />
      </g>
    </g>`;
}

function screenshotArtwork({ width, height, platform, slide, index }) {
  const apple = platform === 'app-store';
  const id = `${platform}-${index}`;
  const background = apple ? colours.navy : colours.paper;
  const foreground = apple ? colours.white : colours.ink;
  const bodyColour = apple ? colours.white : colours.muted;
  const logoY = apple ? 80 : 42;
  const logoScale = apple ? 0.88 : 0.66;
  const headlineY = apple ? 355 : 205;
  const headlineSize = apple ? 86 : 62;
  const headlineLine = apple ? 104 : 78;
  const bodyY = apple ? 595 : 365;
  const bodySize = apple ? 31 : 24;
  const bodyLine = apple ? 46 : 34;
  const phone = apple
    ? { x: 165, y: 820, width: 990, height: 2190 }
    : { x: 140, y: 490, width: 800, height: 1780 };

  const ambient = apple
    ? `
      <g filter="url(#ambient-${id})" opacity="0.9">
        <circle cx="280" cy="1760" r="220" fill="#FFD12E" />
        <circle cx="1020" cy="1710" r="190" fill="#F25A80" />
        <circle cx="845" cy="2260" r="185" fill="#28AA63" />
        <circle cx="420" cy="2370" r="170" fill="#FF7B3D" />
      </g>`
    : `
      <g filter="url(#ambient-${id})" opacity="0.34">
        <circle cx="180" cy="1120" r="170" fill="#FFD12E" />
        <circle cx="930" cy="1060" r="160" fill="#F25A80" />
        <circle cx="820" cy="1600" r="140" fill="#FF9A55" />
      </g>`;

  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
  ${sharedDefs(id)}
  <rect width="${width}" height="${height}" fill="${background}" />
  ${ambient}
  ${brandLockup({ x: width / 2, y: logoY, colour: foreground, scale: logoScale, centered: true })}
  <text x="${width / 2}" y="${headlineY}" text-anchor="middle" class="display" font-size="${headlineSize}" fill="${foreground}" letter-spacing="-2.2">
    <tspan x="${width / 2}" dy="0">${slide.headline[0]}</tspan>
    <tspan x="${width / 2}" dy="${headlineLine}">${slide.headline[1]}</tspan>
  </text>
  <text x="${width / 2}" y="${bodyY}" text-anchor="middle" class="body" font-size="${bodySize}" fill="${bodyColour}" opacity="${apple ? 0.9 : 0.88}">
    <tspan x="${width / 2}" dy="0">${slide.body[0]}</tspan>
    <tspan x="${width / 2}" dy="${bodyLine}">${slide.body[1]}</tspan>
  </text>
  ${phoneMockup({ ...phone, source: slide.source, id, platform })}
</svg>`;
}

function featureGraphic() {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="500" viewBox="0 0 1024 500">
  <defs>
    <style>${fontStyles}</style>
    <clipPath id="feature-photo"><rect width="512" height="500" /></clipPath>
    <linearGradient id="photo-fade" x1="0" y1="0" x2="1" y2="0"><stop offset="0.72" stop-color="#201D31" stop-opacity="0"/><stop offset="1" stop-color="#201D31"/></linearGradient>
  </defs>
  <rect width="1024" height="500" fill="${colours.navy}" />
  <g clip-path="url(#feature-photo)">
    <image href="${originalFeatureData}" x="0" y="0" width="1286" height="628" preserveAspectRatio="xMinYMid slice" />
    <rect x="370" width="142" height="500" fill="url(#photo-fade)" />
  </g>
  ${brandLockup({ x: 560, y: 130, colour: colours.white, scale: 0.95 })}
  <line x1="560" y1="258" x2="955" y2="258" stroke="#FFFFFF" stroke-width="2" opacity="0.9" />
  <text x="560" y="318" class="label" font-size="24" fill="${colours.yellow}">Your whole shop, in your pocket.</text>
  <text x="560" y="364" class="body" font-size="17" fill="${colours.white}" opacity="0.8">Orders · Customers · Stock · Sales</text>
</svg>`;
}

function launchBanner() {
  const screen = dataUri(resolve(rawRoot, 'android/02-products.png'));
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <defs>
    <style>${fontStyles}</style>
    <clipPath id="banner-screen"><rect x="845" y="58" width="270" height="590" rx="34" /></clipPath>
    <filter id="banner-shadow" x="-30%" y="-20%" width="160%" height="160%"><feDropShadow dx="0" dy="22" stdDeviation="20" flood-color="#080610" flood-opacity="0.38" /></filter>
    <filter id="banner-glow" x="-80%" y="-80%" width="260%" height="260%"><feGaussianBlur stdDeviation="70" /></filter>
  </defs>
  <rect width="1200" height="630" fill="${colours.navy}" />
  <g filter="url(#banner-glow)" opacity="0.64">
    <circle cx="1020" cy="170" r="110" fill="#F25A80" />
    <circle cx="825" cy="500" r="130" fill="#FFC629" />
  </g>
  ${brandLockup({ x: 78, y: 58, colour: colours.white, scale: 0.9 })}
  <text x="78" y="276" class="display" font-size="66" fill="${colours.white}" letter-spacing="-2">
    <tspan x="78" dy="0">Your whole shop,</tspan>
    <tspan x="78" dy="80">in your pocket.</tspan>
  </text>
  <text x="78" y="438" class="body" font-size="25" fill="${colours.white}" opacity="0.86">
    <tspan x="78" dy="0">Run the daily work behind the counter</tspan>
    <tspan x="78" dy="38">from one simple app.</tspan>
  </text>
  <text x="78" y="548" class="label" font-size="17" fill="${colours.yellow}" letter-spacing="1.2">ORDERS · BALANCES · STOCK · SALES</text>
  <g filter="url(#banner-shadow)">
    <rect x="831" y="44" width="298" height="650" rx="48" fill="#0C0C0C" stroke="#5B5B5B" stroke-width="3" />
    <g clip-path="url(#banner-screen)"><rect x="845" y="58" width="270" height="590" fill="#FFFFFF"/><image href="${screen}" x="845" y="58" width="270" height="600" preserveAspectRatio="xMidYMin slice" /></g>
  </g>
</svg>`;
}

function appIcon(size) {
  const inset = Math.round(size * 0.20);
  const cartSize = size - inset * 2;
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <rect width="${size}" height="${size}" fill="${colours.navy}" />
  <image href="${cartData}" x="${inset}" y="${inset}" width="${cartSize}" height="${cartSize}" />
</svg>`;
}

function horizontalLogo(colour) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1400" height="360" viewBox="0 0 1400 360">
  <defs><style>${fontStyles}</style></defs>
  ${brandLockup({ x: 44, y: 30, colour, scale: 2.55 })}
</svg>`;
}

function socialLockup(withTagline) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
  <defs><style>${fontStyles}</style></defs>
  <rect width="512" height="512" fill="${colours.navy}" />
  <image href="${cartData}" x="190" y="72" width="132" height="132" />
  <text x="256" y="316" text-anchor="middle" class="brand" font-size="67" fill="${colours.white}" letter-spacing="-2">SpazaOne</text>
  <line x1="60" y1="360" x2="452" y2="360" stroke="#FFFFFF" stroke-width="2" opacity="0.92" />
  ${withTagline ? `<text x="256" y="414" text-anchor="middle" class="label" font-size="20" fill="${colours.yellow}">Your whole shop, in your pocket.</text>` : ''}
</svg>`;
}

function writeSvg(file, content) {
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, content);
}

async function renderSvg(browser, svgPath, pngPath, width, height, transparent = false) {
  mkdirSync(dirname(pngPath), { recursive: true });
  const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
  try {
    await page.goto(pathToFileURL(svgPath).href, { waitUntil: 'load' });
    await page.evaluate(async () => { if (document.fonts) await document.fonts.ready; });
    await page.screenshot({ path: pngPath, type: 'png', clip: { x: 0, y: 0, width, height }, omitBackground: transparent, animations: 'disabled' });
  } finally {
    await page.close();
  }
  if (!existsSync(pngPath)) throw new Error(`Chromium failed to render ${svgPath}`);
}

function flattenPng(file, targetWidth, targetHeight) {
  const script = [
    'from PIL import Image',
    'import sys',
    'path, expected_w, expected_h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])',
    'image = Image.open(path)',
    'assert image.size == (expected_w, expected_h), f"unexpected dimensions: {image.size}"',
    'image.convert("RGB").save(path, format="PNG", optimize=True)',
  ].join('; ');
  const result = spawnSync(python, ['-c', script, file, String(targetWidth), String(targetHeight)], {
    encoding: 'utf8',
    env: { ...process.env, PYTHONPATH: pythonPath },
  });
  if (result.status !== 0) throw new Error(`Could not flatten ${file}: ${result.stderr || result.stdout}`);
}

function contactSheet(platform, files, width, height) {
  const thumbWidth = platform === 'app-store' ? 264 : 270;
  const thumbHeight = Math.round((thumbWidth / width) * height);
  const gutter = 28;
  const margin = 42;
  const sheetWidth = margin * 2 + thumbWidth * files.length + gutter * (files.length - 1);
  const sheetHeight = thumbHeight + 196;
  const title = platform === 'app-store' ? 'SpazaOne · Apple App Store artwork proof' : 'SpazaOne · Google Play artwork proof';
  const note = platform === 'app-store'
    ? 'The visual system is final-direction. Replace Android captures in frames 2–6 with final iOS captures before submission.'
    : 'Uses current release captures. Recapture after the pending app branch lands, then run the same production template.';
  const cards = files.map((file, index) => {
    const x = margin + index * (thumbWidth + gutter);
    return `<g transform="translate(${x} 132)"><rect x="-7" y="-7" width="${thumbWidth + 14}" height="${thumbHeight + 14}" rx="18" fill="#FFFFFF" opacity="0.12"/><image href="${dataUri(file)}" width="${thumbWidth}" height="${thumbHeight}"/><text x="${thumbWidth / 2}" y="${thumbHeight + 47}" text-anchor="middle" class="label" font-size="17" fill="#FFFFFF">${String(index + 1).padStart(2, '0')}</text></g>`;
  }).join('');
  return {
    width: sheetWidth,
    height: sheetHeight,
    svg: `<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" width="${sheetWidth}" height="${sheetHeight}" viewBox="0 0 ${sheetWidth} ${sheetHeight}"><defs><style>${fontStyles}</style></defs><rect width="${sheetWidth}" height="${sheetHeight}" fill="${colours.navy}"/><text x="${margin}" y="49" class="display" font-size="31" fill="#FFFFFF">${title}</text><text x="${margin}" y="85" class="body" font-size="16" fill="#FFFFFF" opacity="0.7">${note}</text>${cards}</svg>`,
  };
}

const renderJobs = [];

for (const platform of ['app-store', 'google-play']) {
  const dimensions = platform === 'app-store' ? { width: 1320, height: 2868 } : { width: 1080, height: 1920 };
  slides.forEach((slide, index) => {
    const svgPath = resolve(productionRoot, `source/${platform}/${slide.slug}.svg`);
    const pngPath = resolve(productionRoot, `draft/${platform}/${slide.slug}.png`);
    writeSvg(svgPath, screenshotArtwork({ ...dimensions, platform, slide, index }));
    renderJobs.push({ ...dimensions, svgPath, pngPath });
  });
}

const featureSvg = resolve(productionRoot, 'source/google-play/00-feature-graphic.svg');
const featurePng = resolve(productionRoot, 'draft/google-play/00-feature-graphic.png');
writeSvg(featureSvg, featureGraphic());
renderJobs.push({ width: 1024, height: 500, svgPath: featureSvg, pngPath: featurePng });

const bannerSvg = resolve(productionRoot, 'source/00-spazaone-launch-banner.svg');
const bannerPng = resolve(productionRoot, 'draft/00-spazaone-launch-banner.png');
writeSvg(bannerSvg, launchBanner());
renderJobs.push({ width: 1200, height: 630, svgPath: bannerSvg, pngPath: bannerPng });

for (const [size, name] of [[1024, 'spazaone-app-store-1024'], [512, 'spazaone-google-play-512']]) {
  const svgPath = resolve(productionRoot, `source/icons/${name}.svg`);
  const pngPath = resolve(productionRoot, `icons/${name}.png`);
  writeSvg(svgPath, appIcon(size));
  renderJobs.push({ width: size, height: size, svgPath, pngPath });
}

for (const [name, colour] of [['spazaone-logo-white', colours.white], ['spazaone-logo-dark', colours.navy]]) {
  const svgPath = resolve(productionRoot, `source/logos/${name}.svg`);
  const pngPath = resolve(productionRoot, `logos/${name}.png`);
  writeSvg(svgPath, horizontalLogo(colour));
  renderJobs.push({ width: 1400, height: 360, svgPath, pngPath, transparent: true });
}

for (const [name, withTagline] of [['spazaone-whatsapp-512', false], ['spazaone-social-tagline-512', true]]) {
  const svgPath = resolve(productionRoot, `source/logos/${name}.svg`);
  const pngPath = resolve(productionRoot, `logos/${name}.png`);
  writeSvg(svgPath, socialLockup(withTagline));
  renderJobs.push({ width: 512, height: 512, svgPath, pngPath });
}

const browser = await chromium.launch({ executablePath: headlessShell, headless: true });
try {
  for (const job of renderJobs) {
    await renderSvg(browser, job.svgPath, job.pngPath, job.width, job.height, job.transparent);
    if (!job.transparent) flattenPng(job.pngPath, job.width, job.height);
    console.log(`Rendered ${job.pngPath}`);
  }

  for (const platform of ['app-store', 'google-play']) {
    const dimensions = platform === 'app-store' ? { width: 1320, height: 2868 } : { width: 1080, height: 1920 };
    const files = slides.map((slide) => resolve(productionRoot, `draft/${platform}/${slide.slug}.png`));
    const sheet = contactSheet(platform, files, dimensions.width, dimensions.height);
    const svgPath = resolve(productionRoot, `review/${platform}-contact-sheet.svg`);
    const pngPath = resolve(productionRoot, `review/${platform}-contact-sheet.png`);
    writeSvg(svgPath, sheet.svg);
    await renderSvg(browser, svgPath, pngPath, sheet.width, sheet.height);
    flattenPng(pngPath, sheet.width, sheet.height);
    console.log(`Rendered ${pngPath}`);
  }
} finally {
  await browser.close();
}

console.log('SpazaOne ASO artwork rendered successfully.');
