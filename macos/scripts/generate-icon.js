// Pure Node.js generator for 512x512 RGBA PNG app icon (teal rounded square with white "A").
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const SIZE = 512;
const raw = Buffer.alloc((SIZE * 4 + 1) * SIZE);

function inRoundedRect(x, y, size, radius) {
  const dx = Math.max(radius - x, 0, x - (size - 1 - radius));
  const dy = Math.max(radius - y, 0, y - (size - 1 - radius));
  return dx * dx + dy * dy <= radius * radius;
}

function inLetterA(nx, ny) {
  // Normalized coordinates 0..1
  if (ny < 0.22 || ny > 0.78) return false;
  const t = (ny - 0.22) / (0.78 - 0.22); // 0 at top, 1 at bottom
  const halfSpan = 0.045 + t * 0.235;
  const stroke = 0.072;
  const distFromCenter = Math.abs(nx - 0.5);
  // Left & right legs
  if (distFromCenter <= halfSpan && distFromCenter >= Math.max(0, halfSpan - stroke)) return true;
  // Crossbar
  if (ny >= 0.56 && ny <= 0.635 && distFromCenter <= halfSpan - 0.02) return true;
  return false;
}

for (let y = 0; y < SIZE; y++) {
  const rowStart = y * (SIZE * 4 + 1);
  raw[rowStart] = 0; // filter type None
  for (let x = 0; x < SIZE; x++) {
    const idx = rowStart + 1 + x * 4;
    if (!inRoundedRect(x, y, SIZE, 112)) {
      raw[idx] = 0; raw[idx + 1] = 0; raw[idx + 2] = 0; raw[idx + 3] = 0;
      continue;
    }
    const nx = x / SIZE;
    const ny = y / SIZE;
    if (inLetterA(nx, ny)) {
      raw[idx] = 255; raw[idx + 1] = 255; raw[idx + 2] = 255; raw[idx + 3] = 255;
    } else {
      // Subtle teal gradient (#0A8F82 -> #06635A)
      raw[idx] = Math.round(10 - ny * 4);
      raw[idx + 1] = Math.round(143 - ny * 44);
      raw[idx + 2] = Math.round(130 - ny * 40);
      raw[idx + 3] = 255;
    }
  }
}

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) {
    c ^= buf[i];
    for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (c & 1 ? 0xedb88320 : 0);
  }
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const t = Buffer.from(type, 'ascii');
  const crcBuf = Buffer.alloc(4);
  crcBuf.writeUInt32BE(crc32(Buffer.concat([t, data])), 0);
  return Buffer.concat([len, t, data, crcBuf]);
}

const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(SIZE, 0);
ihdr.writeUInt32BE(SIZE, 4);
ihdr[8] = 8; // bit depth
ihdr[9] = 6; // RGBA
ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;

const png = Buffer.concat([
  Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
  chunk('IHDR', ihdr),
  chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
  chunk('IEND', Buffer.alloc(0))
]);

const outDir = path.join(__dirname, '..', 'build');
fs.mkdirSync(outDir, { recursive: true });
const outPath = path.join(outDir, 'icon.png');
fs.writeFileSync(outPath, png);
console.log(`Generated ${outPath} (${png.length} bytes)`);
