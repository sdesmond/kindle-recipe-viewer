#!/usr/bin/env node

import { lstatSync, mkdirSync, rmSync, symlinkSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

function ensureDirectoryLink(rootDir, linkPath, targetPath) {
  mkdirSync(targetPath, { recursive: true });
  mkdirSync(dirname(linkPath), { recursive: true });

  let existingStats;
  try {
    existingStats = lstatSync(linkPath);
  } catch {
    existingStats = null;
  }

  if (existingStats) {
    if (!existingStats.isSymbolicLink()) {
      throw new Error(
        `Refusing to replace existing path: ${relative(rootDir, linkPath)}`,
      );
    }

    rmSync(linkPath, { recursive: true, force: true });
  }

  const symlinkTarget =
    process.platform === "win32"
      ? targetPath
      : relative(dirname(linkPath), targetPath);

  symlinkSync(
    symlinkTarget,
    linkPath,
    process.platform === "win32" ? "junction" : "dir",
  );
}

export function ensureAiToolLinks(rootDir) {
  ensureDirectoryLink(
    rootDir,
    join(rootDir, ".claude", "skills"),
    join(rootDir, ".agents", "skills"),
  );
}

const scriptPath = fileURLToPath(import.meta.url);

if (process.argv[1] && resolve(process.argv[1]) === scriptPath) {
  const rootDir = resolve(process.cwd());
  ensureAiToolLinks(rootDir);
  console.log("Linked .claude/skills to .agents/skills.");
}
