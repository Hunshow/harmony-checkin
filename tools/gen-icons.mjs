#!/usr/bin/env node
/**
 * 生成应用图标 PNG（无第三方依赖）
 * ------------------------------------------------------------------
 * 手写 PNG 编码器：zlib 用 Node 内置模块，CRC32 自行实现。
 * 这样在没有任何图形库的 CI 环境里也能一键生成图标，方便开源项目贡献者复现。
 *
 * 用法：node tools/gen-icons.mjs
 */
import { deflateSync } from 'node:zlib';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MEDIA_DIR = resolve(__dirname, '../AppScope/resources/base/media');

const SIZE = 216;

// ---------------- PNG 编码 ----------------

const CRC_TABLE = (() => {
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c;
  }
  return table;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) {
    c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const typeBuf = Buffer.from(type, 'ascii');
  const body = Buffer.concat([typeBuf, data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}

/** 把 RGBA 像素数组编码为 PNG */
function encodePng(width, height, rgba) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;   // bit depth
  ihdr[9] = 6;   // color type: RGBA
  ihdr[10] = 0;  // compression
  ihdr[11] = 0;  // filter
  ihdr[12] = 0;  // interlace

  // 每行前加一个 filter 字节（0 = None）
  const raw = Buffer.alloc(height * (width * 4 + 1));
  for (let y = 0; y < height; y++) {
    raw[y * (width * 4 + 1)] = 0;
    rgba.copy(raw, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  }

  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ---------------- 绘制 ----------------

const hex = (s) => [
  parseInt(s.slice(1, 3), 16),
  parseInt(s.slice(3, 5), 16),
  parseInt(s.slice(5, 7), 16),
];

const BLUE = hex('#2563EB');
const BLUE_DARK = hex('#1D4ED8');
const BLUE_LIGHT = hex('#DBEAFE');
const WHITE = hex('#FFFFFF');

/** 创建画布 */
function createCanvas(size, bg) {
  const buf = Buffer.alloc(size * size * 4);
  for (let i = 0; i < size * size; i++) {
    buf[i * 4] = bg[0];
    buf[i * 4 + 1] = bg[1];
    buf[i * 4 + 2] = bg[2];
    buf[i * 4 + 3] = 255;
  }
  return buf;
}

/** 混合一个像素（带 alpha 抗锯齿） */
function blend(buf, size, x, y, color, alpha) {
  if (x < 0 || y < 0 || x >= size || y >= size || alpha <= 0) return;
  const i = (y * size + x) * 4;
  const a = Math.max(0, Math.min(1, alpha));
  buf[i] = Math.round(buf[i] * (1 - a) + color[0] * a);
  buf[i + 1] = Math.round(buf[i + 1] * (1 - a) + color[1] * a);
  buf[i + 2] = Math.round(buf[i + 2] * (1 - a) + color[2] * a);
  buf[i + 3] = 255;
}

/** 圆角矩形（超采样 4x4 抗锯齿） */
function fillRoundRect(buf, size, x, y, w, h, r, color) {
  for (let py = y; py < y + h; py++) {
    for (let px = x; px < x + w; px++) {
      let hits = 0;
      for (let sy = 0; sy < 4; sy++) {
        for (let sx = 0; sx < 4; sx++) {
          const fx = px + (sx + 0.5) / 4;
          const fy = py + (sy + 0.5) / 4;
          // 判断是否落在圆角矩形内
          const cx = Math.min(Math.max(fx, x + r), x + w - r);
          const cy = Math.min(Math.max(fy, y + r), y + h - r);
          const dx = fx - cx;
          const dy = fy - cy;
          if (dx * dx + dy * dy <= r * r) hits++;
        }
      }
      if (hits > 0) blend(buf, size, px, py, color, hits / 16);
    }
  }
}

/** 圆形 */
function fillCircle(buf, size, cx, cy, r, color) {
  for (let py = Math.floor(cy - r - 1); py <= Math.ceil(cy + r + 1); py++) {
    for (let px = Math.floor(cx - r - 1); px <= Math.ceil(cx + r + 1); px++) {
      let hits = 0;
      for (let sy = 0; sy < 4; sy++) {
        for (let sx = 0; sx < 4; sx++) {
          const dx = px + (sx + 0.5) / 4 - cx;
          const dy = py + (sy + 0.5) / 4 - cy;
          if (dx * dx + dy * dy <= r * r) hits++;
        }
      }
      if (hits > 0) blend(buf, size, px, py, color, hits / 16);
    }
  }
}

/** 粗线段（圆头），用于画对勾 */
function drawThickLine(buf, size, x1, y1, x2, y2, width, color) {
  const half = width / 2;
  const minX = Math.floor(Math.min(x1, x2) - half - 1);
  const maxX = Math.ceil(Math.max(x1, x2) + half + 1);
  const minY = Math.floor(Math.min(y1, y2) - half - 1);
  const maxY = Math.ceil(Math.max(y1, y2) + half + 1);

  const vx = x2 - x1;
  const vy = y2 - y1;
  const len2 = vx * vx + vy * vy;

  for (let py = minY; py <= maxY; py++) {
    for (let px = minX; px <= maxX; px++) {
      let hits = 0;
      for (let sy = 0; sy < 4; sy++) {
        for (let sx = 0; sx < 4; sx++) {
          const fx = px + (sx + 0.5) / 4;
          const fy = py + (sy + 0.5) / 4;
          // 投影参数
          let t = len2 === 0 ? 0 : ((fx - x1) * vx + (fy - y1) * vy) / len2;
          t = Math.max(0, Math.min(1, t));
          const dx = fx - (x1 + t * vx);
          const dy = fy - (y1 + t * vy);
          if (dx * dx + dy * dy <= half * half) hits++;
        }
      }
      if (hits > 0) blend(buf, size, px, py, color, hits / 16);
    }
  }
}

/** 绘制图标：蓝色圆角底 + 白色签到卡 + 蓝色对勾 + 顶部两个卡扣 */
function drawIcon(size, withBackground) {
  const buf = createCanvas(size, withBackground ? BLUE : [255, 255, 255]);
  const k = size / 216; // 以 216 为基准等比缩放，便于输出多尺寸

  const s = (v) => Math.round(v * k);

  if (withBackground) {
    fillRoundRect(buf, size, 0, 0, size, size, s(48), BLUE);
  }

  // 卡扣（先画，被卡片压住上沿更自然）
  fillRoundRect(buf, size, s(80), s(34), s(14), s(30), s(7), BLUE_DARK);
  fillRoundRect(buf, size, s(122), s(34), s(14), s(30), s(7), BLUE_DARK);

  // 卡片主体
  fillRoundRect(buf, size, s(44), s(50), s(128), s(116), s(18), WHITE);

  // 圆形底衬 + 对勾
  fillCircle(buf, size, s(108), s(122), s(32), BLUE_LIGHT);
  drawThickLine(buf, size, s(92), s(122), s(104), s(134), s(10), BLUE);
  drawThickLine(buf, size, s(104), s(134), s(126), s(110), s(10), BLUE);

  return buf;
}

// ---------------- 输出 ----------------

mkdirSync(MEDIA_DIR, { recursive: true });

const main = encodePng(SIZE, SIZE, drawIcon(SIZE, true));
writeFileSync(resolve(MEDIA_DIR, 'app_icon.png'), main);
writeFileSync(resolve(MEDIA_DIR, 'startIcon.png'), main);
writeFileSync(resolve(MEDIA_DIR, 'layered_image.png'), main);
// 分层图标：背景层（纯蓝）+ 前景层（白底图形），供桌面图标使用
writeFileSync(resolve(MEDIA_DIR, 'background.png'), encodePng(SIZE, SIZE, drawIcon(SIZE, true)));
writeFileSync(resolve(MEDIA_DIR, 'foreground.png'), encodePng(SIZE, SIZE, drawIcon(SIZE, false)));

console.log(`图标已生成到 ${MEDIA_DIR}`);
console.log('  app_icon.png / startIcon.png / layered_image.png / background.png / foreground.png');
