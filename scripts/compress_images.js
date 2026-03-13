/**
 * Compress and resize images in the assets/ folder.
 *
 * - Resizes any image wider than 1920px to 1920px (aspect ratio preserved).
 * - Saves JPEGs at quality 75 and PNGs with maximum compression.
 * - Overwrites originals in-place (run on a committed repo so you can revert).
 *
 * Usage:
 *     cd scripts && npm install sharp && cd ..
 *     node scripts/compress_images.js
 */

const fs = require("fs");
const path = require("path");
const sharp = require("sharp");

const ASSETS_DIR = path.resolve(__dirname, "..", "assets");
const MAX_WIDTH = 1920;
const JPEG_QUALITY = 75;
const EXTENSIONS = new Set([".jpg", ".jpeg", ".png"]);

function humanSize(bytes) {
  for (const unit of ["B", "KB", "MB"]) {
    if (Math.abs(bytes) < 1024) return `${bytes.toFixed(2)} ${unit}`;
    bytes /= 1024;
  }
  return `${bytes.toFixed(2)} GB`;
}

function findImages(dir) {
  const results = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...findImages(full));
    } else if (EXTENSIONS.has(path.extname(entry.name).toLowerCase())) {
      results.push(full);
    }
  }
  return results.sort();
}

async function compressImage(filePath) {
  const originalSize = fs.statSync(filePath).size;
  const ext = path.extname(filePath).toLowerCase();

  let pipeline = sharp(filePath, { failOn: "none" })
    .rotate() // auto-rotate based on EXIF
    .resize({ width: MAX_WIDTH, withoutEnlargement: true });

  const tmpPath = filePath + ".tmp";

  if (ext === ".png") {
    await pipeline.png({ quality: JPEG_QUALITY, effort: 10 }).toFile(tmpPath);
  } else {
    await pipeline
      .jpeg({ quality: JPEG_QUALITY, mozjpeg: true })
      .toFile(tmpPath);
  }

  fs.renameSync(tmpPath, filePath);
  const newSize = fs.statSync(filePath).size;
  return { originalSize, newSize };
}

async function main() {
  if (!fs.existsSync(ASSETS_DIR)) {
    console.error(`Assets directory not found: ${ASSETS_DIR}`);
    process.exit(1);
  }

  const files = findImages(ASSETS_DIR);
  if (files.length === 0) {
    console.log("No image files found.");
    return;
  }

  const COL = { file: 60, size: 12 };
  const header =
    "File".padEnd(COL.file) +
    "Before".padStart(COL.size) +
    "After".padStart(COL.size) +
    "Saved".padStart(COL.size);
  console.log(header);
  console.log("-".repeat(header.length));

  let totalBefore = 0;
  let totalAfter = 0;

  for (const f of files) {
    try {
      const { originalSize, newSize } = await compressImage(f);
      totalBefore += originalSize;
      totalAfter += newSize;
      const saved = originalSize - newSize;
      const rel = path.relative(ASSETS_DIR, f);
      console.log(
        rel.padEnd(COL.file) +
          humanSize(originalSize).padStart(COL.size) +
          humanSize(newSize).padStart(COL.size) +
          humanSize(saved).padStart(COL.size)
      );
    } catch (e) {
      console.error(`  ERROR ${path.relative(ASSETS_DIR, f)}: ${e.message}`);
    }
  }

  console.log("-".repeat(header.length));
  console.log(
    "TOTAL".padEnd(COL.file) +
      humanSize(totalBefore).padStart(COL.size) +
      humanSize(totalAfter).padStart(COL.size) +
      humanSize(totalBefore - totalAfter).padStart(COL.size)
  );
  const pct = totalBefore
    ? (((totalBefore - totalAfter) / totalBefore) * 100).toFixed(1)
    : "0.0";
  console.log(`\nReduction: ${pct}%`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
