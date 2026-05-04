import path from "node:path";
import process from "node:process";
import { mkdir, writeFile } from "node:fs/promises";

import { Document, HeadingLevel, Packer, Paragraph, TextRun } from "docx";
import { JSDOM, VirtualConsole } from "jsdom";

const DEFAULT_OUTPUT_ROOT = path.resolve("dist", "podcast-docs");
const USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0 Safari/537.36";

function normalizeWhitespace(value) {
  return value.replace(/\u00a0/g, " ").replace(/\s+/g, " ").trim();
}

function sanitizeFileName(value) {
  const cleaned = value
    .replace(/[<>:"/\\|?*\u0000-\u001f]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/[. ]+$/g, "");

  return cleaned || "untitled";
}

function slugify(value) {
  return (
    value
      .toLowerCase()
      .replace(/&/g, " and ")
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "") || "podcast"
  );
}

function toDateSlug(dateTime) {
  if (!dateTime) {
    return "";
  }

  const date = new Date(dateTime);
  if (Number.isNaN(date.getTime())) {
    return "";
  }

  return date.toISOString().slice(0, 10);
}

function formatDate(dateTime) {
  if (!dateTime) {
    return "";
  }

  const date = new Date(dateTime);
  if (Number.isNaN(date.getTime())) {
    return "";
  }

  return new Intl.DateTimeFormat("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
  }).format(date);
}

function buildDom(html) {
  const virtualConsole = new VirtualConsole();
  virtualConsole.on("jsdomError", () => {});
  return new JSDOM(html, { virtualConsole });
}

async function fetchText(url) {
  const response = await fetch(url, {
    headers: {
      "User-Agent": USER_AGENT,
      "Accept-Language": "en-US,en;q=0.9",
    },
  });

  if (!response.ok) {
    throw new Error(`Failed to fetch ${url}: ${response.status} ${response.statusText}`);
  }

  return response.text();
}

function parseJsonScript(document, id) {
  const raw = document.querySelector(`script#${id}`)?.textContent?.trim();
  if (!raw) {
    return null;
  }

  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function extractDescriptionParagraphs(document) {
  const aboutCard = [...document.querySelectorAll(".ln-page-card")].find((card) => {
    const heading = normalizeWhitespace(card.querySelector("h2")?.textContent ?? "");
    return heading === "ABOUT THIS EPISODE";
  });

  if (!aboutCard) {
    return [];
  }

  const paragraphs = [...aboutCard.querySelectorAll(".ln-text-links p")]
    .map((paragraph) => normalizeWhitespace(paragraph.textContent ?? ""))
    .filter(Boolean);

  return paragraphs;
}

function extractTranscriptParagraphs(transcript) {
  if (typeof transcript !== "string" || !transcript.trim()) {
    return [];
  }

  if (transcript.includes("<")) {
    const fragment = JSDOM.fragment(`<div>${transcript}</div>`);
    const blocks = [...fragment.querySelectorAll("p, li, h2, h3, h4, blockquote")]
      .map((node) => normalizeWhitespace(node.textContent ?? ""))
      .filter(Boolean);

    if (blocks.length > 0) {
      return blocks;
    }
  }

  return transcript
    .split(/\n{2,}/)
    .map((block) => normalizeWhitespace(block))
    .filter(Boolean);
}

function buildEpisodeFileName(episode, index) {
  const datePrefix = toDateSlug(episode.publishedAt) || `episode-${String(index + 1).padStart(2, "0")}`;
  const title = sanitizeFileName(episode.title);
  const baseName = `${datePrefix} - ${title}`;
  const truncated = baseName.length > 150 ? baseName.slice(0, 150).trim() : baseName;
  return `${truncated}.docx`;
}

async function scrapeShow(showUrl) {
  const html = await fetchText(showUrl);
  const document = buildDom(html).window.document;
  const showTitle =
    document.querySelector('meta[property="og:title"]')?.getAttribute("content")?.trim() ||
    normalizeWhitespace(document.querySelector("h1")?.textContent ?? "") ||
    "Podcast";

  const players = [...document.querySelectorAll('div[data-type="episode-audio-player"]')];
  const playerByTitle = new Map(
    players.map((player) => [normalizeWhitespace(player.dataset.title ?? ""), player]),
  );

  const episodes = [...document.querySelectorAll('h3 a[href*="/podcasts/"]')]
    .map((anchor) => {
      const title = normalizeWhitespace(anchor.textContent ?? "");
      const detailsContainer = anchor.closest("h3")?.parentElement;
      const time = detailsContainer?.querySelector("time[datetime]");
      const player = playerByTitle.get(title);

      return {
        title,
        episodeUrl: anchor.href,
        publishedAt: time?.getAttribute("datetime")?.trim() ?? "",
        publishedLabel: normalizeWhitespace(time?.textContent ?? ""),
        duration: normalizeWhitespace(player?.dataset.duration ?? ""),
      };
    })
    .filter((episode) => episode.title && episode.episodeUrl);

  if (episodes.length === 0) {
    throw new Error("No episodes were found on the Listen Notes show page.");
  }

  return {
    showTitle,
    showUrl,
    episodes,
  };
}

async function scrapeEpisodeDetails(episode) {
  const html = await fetchText(episode.episodeUrl);
  const document = buildDom(html).window.document;
  const originalContent = parseJsonScript(document, "original-content") ?? {};
  const descriptionParagraphs = extractDescriptionParagraphs(document);
  const transcriptParagraphs = extractTranscriptParagraphs(originalContent.transcript);

  return {
    ...episode,
    duration: episode.duration || normalizeWhitespace(originalContent.audio_length ?? ""),
    audioUrl: typeof originalContent.audio === "string" ? originalContent.audio.trim() : "",
    descriptionParagraphs,
    transcriptParagraphs,
  };
}

function buildDocChildren(showTitle, episode) {
  const metadataRows = [
    ["Podcast", showTitle],
    ["Published", episode.publishedLabel || formatDate(episode.publishedAt)],
    ["Duration", episode.duration],
    ["Episode URL", episode.episodeUrl],
    ["Audio URL", episode.audioUrl],
  ].filter(([, value]) => value);

  const children = [
    new Paragraph({
      text: episode.title,
      heading: HeadingLevel.HEADING_1,
    }),
  ];

  for (const [label, value] of metadataRows) {
    children.push(
      new Paragraph({
        children: [
          new TextRun({ text: `${label}: `, bold: true }),
          new TextRun(String(value)),
        ],
      }),
    );
  }

  children.push(new Paragraph({}));
  children.push(
    new Paragraph({
      text: "About This Episode",
      heading: HeadingLevel.HEADING_2,
    }),
  );

  const descriptionParagraphs =
    episode.descriptionParagraphs.length > 0
      ? episode.descriptionParagraphs
      : ["No description was found on the episode page."];

  for (const paragraph of descriptionParagraphs) {
    children.push(new Paragraph({ text: paragraph }));
  }

  if (episode.transcriptParagraphs.length > 0) {
    children.push(new Paragraph({}));
    children.push(
      new Paragraph({
        text: "Transcript",
        heading: HeadingLevel.HEADING_2,
      }),
    );

    for (const paragraph of episode.transcriptParagraphs) {
      children.push(new Paragraph({ text: paragraph }));
    }
  }

  return children;
}

async function writeEpisodeDocx(showTitle, outputDirectory, episode, index) {
  const document = new Document({
    sections: [
      {
        children: buildDocChildren(showTitle, episode),
      },
    ],
  });

  const fileName = buildEpisodeFileName(episode, index);
  const filePath = path.join(outputDirectory, fileName);
  const buffer = await Packer.toBuffer(document);

  await writeFile(filePath, buffer);

  return {
    ...episode,
    fileName,
    filePath,
  };
}

function printUsageAndExit() {
  console.error("Usage: npm run podcast:word -- <listen-notes-show-url> [output-directory]");
  process.exit(1);
}

async function main() {
  const [showUrl, outputRootArg] = process.argv.slice(2);

  if (!showUrl) {
    printUsageAndExit();
  }

  const outputRoot = path.resolve(outputRootArg ?? DEFAULT_OUTPUT_ROOT);
  const show = await scrapeShow(showUrl);
  const outputDirectory = path.join(outputRoot, slugify(show.showTitle));

  await mkdir(outputDirectory, { recursive: true });

  const exportedEpisodes = [];

  for (const [index, episode] of show.episodes.entries()) {
    const fullEpisode = await scrapeEpisodeDetails(episode);
    const exportedEpisode = await writeEpisodeDocx(show.showTitle, outputDirectory, fullEpisode, index);
    exportedEpisodes.push({
      title: exportedEpisode.title,
      publishedAt: exportedEpisode.publishedAt,
      publishedLabel: exportedEpisode.publishedLabel,
      duration: exportedEpisode.duration,
      fileName: exportedEpisode.fileName,
      episodeUrl: exportedEpisode.episodeUrl,
      audioUrl: exportedEpisode.audioUrl,
    });
  }

  const manifestPath = path.join(outputDirectory, "manifest.json");
  await writeFile(
    manifestPath,
    JSON.stringify(
      {
        generatedAt: new Date().toISOString(),
        showTitle: show.showTitle,
        showUrl: show.showUrl,
        episodeCount: exportedEpisodes.length,
        episodes: exportedEpisodes,
      },
      null,
      2,
    ),
  );

  console.log(`Exported ${exportedEpisodes.length} episodes to ${outputDirectory}`);
  console.log(`Manifest written to ${manifestPath}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
