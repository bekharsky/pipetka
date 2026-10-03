import { readFileSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const assets = join(projectRoot, "docs", "assets");
const screenshot = readFileSync(join(assets, "pipetka-palette.png")).toString("base64");
const moodboard = readFileSync(join(assets, "atelier-moodboard-08.png")).toString("base64");
const frameDirectory = mkdtempSync(join(tmpdir(), "pipetka-demo-"));

const width = 1600;
const height = 900;
const fps = 24;
const duration = 8;
const frameCount = fps * duration;
const colors = [
  { name: "Parchment", value: "#EEE3D0" },
  { name: "Bouquet", value: "#AD839C" },
  { name: "Rob Roy", value: "#E8C27B" },
  { name: "Smalt Blue", value: "#578E83" },
  { name: "Tuna", value: "#2A3A4C" },
  { name: "Japonica", value: "#D18062" },
  { name: "Summer Green", value: "#94B6A3" },
  { name: "Abbey", value: "#4E5152" },
];

function clamp(value, min = 0, max = 1) {
  return Math.max(min, Math.min(max, value));
}

function ease(value) {
  const t = clamp(value);
  return t * t * (3 - 2 * t);
}

function xml(value) {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

function rowMarkup(color, index, time) {
  const enterAt = 1.15 + index * 0.34;
  const enter = ease((time - enterAt) / 0.32);
  const leaveAt = 5.7 + (colors.length - index - 1) * 0.2;
  const leave = 1 - ease((time - leaveAt) / 0.28);
  const opacity = Math.min(enter, leave);
  if (opacity < 0.003) return "";

  const x = 652;
  const y = 342 + index * 59;
  const offset = (1 - enter) * 13;
  return `
    <g opacity="${opacity.toFixed(3)}" transform="translate(0 ${offset.toFixed(1)})">
      <rect x="${x}" y="${y}" width="860" height="51" rx="10" fill="#0f1e2b" stroke="#8daeba" stroke-opacity=".13"/>
      <rect x="${x + 13}" y="${y + 9}" width="33" height="33" rx="7" fill="${color.value}" stroke="#ffffff" stroke-opacity=".19"/>
      <text x="${x + 61}" y="${y + 32}" fill="#dce8eb" font-family="Arial, sans-serif" font-size="16" font-weight="700">${xml(color.name)}</text>
      <text x="${x + 829}" y="${y + 32}" text-anchor="end" fill="#bdcbd1" font-family="Menlo, Monaco, monospace" font-size="14">${color.value}</text>
      <circle cx="${x + 847}" cy="${y + 25}" r="2" fill="${color.value}" opacity=".9"/>
    </g>`;
}

function frameSvg(time) {
  const visibleColors = colors.reduce((count, _, index) => {
    const enterAt = 1.15 + index * 0.34;
    const leaveAt = 5.7 + (colors.length - index - 1) * 0.2;
    return count + (time >= enterAt + 0.22 && time < leaveAt + 0.14 ? 1 : 0);
  }, 0);
  const complete = visibleColors === colors.length;
  const pulse = complete ? 0.72 + 0.12 * Math.sin((time - 4) * Math.PI * 1.2) : 0.72;
  const rows = colors.map((color, index) => rowMarkup(color, index, time)).join("");
  const progress = Math.round((time / duration) * 100);
  const entryCount = String(visibleColors).padStart(2, "0");

  return `<?xml version="1.0" encoding="UTF-8"?>
  <svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
    <defs>
      <linearGradient id="page" x1="0" y1="0" x2="1" y2="1">
        <stop stop-color="#08131f"/>
        <stop offset=".56" stop-color="#0a1622"/>
        <stop offset="1" stop-color="#101729"/>
      </linearGradient>
      <linearGradient id="shine" x1="0" y1="0" x2="1" y2="0">
        <stop stop-color="#6cf2ca"/>
        <stop offset=".45" stop-color="#62cfff"/>
        <stop offset=".76" stop-color="#a38aff"/>
        <stop offset="1" stop-color="#ef6fba"/>
      </linearGradient>
      <radialGradient id="halo">
        <stop stop-color="#186986" stop-opacity=".36"/>
        <stop offset="1" stop-color="#091622" stop-opacity="0"/>
      </radialGradient>
      <clipPath id="shot-clip"><rect x="82" y="140" width="500" height="595" rx="17"/></clipPath>
      <clipPath id="board-clip"><rect x="412" y="632" width="176" height="110" rx="12"/></clipPath>
    </defs>
    <rect width="${width}" height="${height}" fill="url(#page)"/>
    <ellipse cx="329" cy="452" rx="405" ry="455" fill="url(#halo)"/>
    <ellipse cx="1290" cy="403" rx="480" ry="385" fill="url(#halo)" opacity=".55"/>
    <ellipse cx="905" cy="450" rx="700" ry="350" fill="none" stroke="#a4d6ea" stroke-opacity=".055" transform="rotate(-11 905 450)"/>
    <ellipse cx="907" cy="447" rx="612" ry="291" fill="none" stroke="#ba9cff" stroke-opacity=".06" transform="rotate(17 907 447)"/>

    <g transform="translate(82 46)">
      <rect width="36" height="36" rx="10" fill="#0e2b64" stroke="#93a6ff" stroke-opacity=".35"/>
      <circle cx="18" cy="18" r="11" fill="none" stroke="url(#shine)" stroke-width="3"/>
      <circle cx="18" cy="18" r="5" fill="#a5b7ff"/>
      <text x="49" y="17" fill="#ebf3f5" font-family="Arial, sans-serif" font-size="16" font-weight="800" letter-spacing="-.5">Pipetka</text>
      <text x="49" y="31" fill="#8498a4" font-family="Menlo, Monaco, monospace" font-size="8" letter-spacing="1.1">COLOR PICKER FOR MAC</text>
    </g>
    <text x="1515" y="70" text-anchor="end" fill="#8798a3" font-family="Menlo, Monaco, monospace" font-size="10" letter-spacing="1.3">MOCK DATA / ORIGINAL ARTWORK</text>

    <rect x="77" y="134" width="510" height="607" rx="20" fill="#ecf1f2" fill-opacity=".15"/>
    <image x="82" y="140" width="500" height="595" href="data:image/png;base64,${screenshot}" clip-path="url(#shot-clip)"/>
    <g transform="rotate(-5 500 687)">
      <rect x="408" y="628" width="184" height="118" rx="14" fill="#102230" stroke="#c5dce3" stroke-opacity=".32"/>
      <image x="412" y="632" width="176" height="110" preserveAspectRatio="xMidYMid slice" href="data:image/png;base64,${moodboard}" clip-path="url(#board-clip)"/>
      <rect x="419" y="640" width="59" height="17" rx="5" fill="#07131e" fill-opacity=".87"/>
      <text x="449" y="652" text-anchor="middle" fill="#e7f1f3" font-family="Menlo, Monaco, monospace" font-size="7" letter-spacing=".8">INPUT IMAGE</text>
    </g>
    <circle cx="560" cy="179" r="6" fill="#6cf2ca" opacity=".8"/>
    <circle cx="560" cy="179" r="15" fill="none" stroke="#6cf2ca" stroke-opacity=".25"/>

    <text x="652" y="165" fill="#75dfd4" font-family="Menlo, Monaco, monospace" font-size="10" letter-spacing="1.8">IMAGE → PALETTE</text>
    <text x="652" y="222" fill="#f0f5f6" font-family="Arial, sans-serif" font-size="45" font-weight="800" letter-spacing="-2.4">A moodboard,</text>
    <text x="652" y="274" fill="url(#shine)" font-family="Arial, sans-serif" font-size="45" font-weight="800" letter-spacing="-2.4">made usable.</text>
    <text x="652" y="307" fill="#a4b4bc" font-family="Arial, sans-serif" font-size="14">Eight demo colors, named and ready to copy.</text>
    <text x="1512" y="306" text-anchor="end" fill="#8fa2ac" font-family="Menlo, Monaco, monospace" font-size="9" letter-spacing="1.2">${entryCount} / 08 FOUND</text>

    <g>${rows}</g>
    <g opacity="${complete ? pulse.toFixed(3) : "0.15"}">
      <rect x="652" y="824" width="860" height="2" rx="1" fill="url(#shine)"/>
    </g>
    <text x="82" y="813" fill="#8ea1ab" font-family="Menlo, Monaco, monospace" font-size="9" letter-spacing="1.1">ATELIER · COLOUR STUDY 08</text>
    <text x="1516" y="852" text-anchor="end" fill="#8799a4" font-family="Menlo, Monaco, monospace" font-size="9" letter-spacing=".9">PICK A PIXEL. KEEP THE COLOR.</text>
    <rect x="82" y="875" width="1436" height="2" rx="1" fill="#172b39"/>
    <rect x="82" y="875" width="${1436 * (progress / 100)}" height="2" rx="1" fill="url(#shine)"/>
  </svg>`;
}

function run(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8", stdio: "pipe" });
  if (result.status !== 0) {
    process.stderr.write(result.stderr || result.stdout || `${command} failed\n`);
    process.exit(result.status ?? 1);
  }
}

mkdirSync(frameDirectory, { recursive: true });
for (let frame = 0; frame < frameCount; frame += 1) {
  const time = frame / fps;
  const svgPath = join(frameDirectory, `frame-${String(frame).padStart(4, "0")}.svg`);
  const pngPath = join(frameDirectory, `frame-${String(frame).padStart(4, "0")}.png`);
  writeFileSync(svgPath, frameSvg(time));
  run("/usr/bin/sips", ["-s", "format", "png", svgPath, "--out", pngPath]);
}

const posterPath = join(assets, "pipetka-demo-poster.jpg");
const posterPng = join(frameDirectory, "poster.png");
const posterSvg = join(frameDirectory, "poster.svg");
writeFileSync(posterSvg, frameSvg(4.9));
run("/usr/bin/sips", ["-s", "format", "png", posterSvg, "--out", posterPng]);
run("/usr/bin/sips", ["-s", "format", "jpeg", "-s", "formatOptions", "85", "-Z", "1280", posterPng, "--out", posterPath]);
run("ffmpeg", [
  "-hide_banner",
  "-loglevel",
  "error",
  "-y",
  "-framerate",
  String(fps),
  "-i",
  join(frameDirectory, "frame-%04d.png"),
  "-an",
  "-c:v",
  "libx264",
  "-preset",
  "medium",
  "-crf",
  "21",
  "-pix_fmt",
  "yuv420p",
  "-movflags",
  "+faststart",
  join(assets, "pipetka-demo.mp4"),
]);

process.stdout.write(`Rendered ${frameCount} frames into docs/assets/pipetka-demo.mp4\n`);
