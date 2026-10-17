/**
 * Detector configuration for the web-ui-design skill.
 *
 * Self-contained: reads an optional project-local ignore config so teams can
 * suppress findings for a deliberate decision. There is no hook or consent
 * state here — that belonged to the upstream multi-command tool, not to a
 * detector that runs when this skill asks it to.
 *
 * Schema, all keys optional:
 *   {
 *     "detector": {
 *       "ignoreRules":  ["overused-font"],        // rule ids to silence project-wide
 *       "ignoreFiles":  ["src/legacy/**"],        // globs excluded from scanning
 *       "ignoreValues": ["color:#fdf6e3"],        // specific values to accept
 *       "designSystem": { "enabled": true }       // compare against project tokens
 *     }
 *   }
 *
 * `config.json` is meant to be committed; `config.local.json` is gitignored
 * and overrides it for one developer.
 */

import { existsSync, readFileSync, statSync } from 'node:fs';
import { join, relative, resolve, sep } from 'node:path';

const CONFIG_DIR = '.web-ui';

export function getConfigPath(root) {
  return join(root, CONFIG_DIR, 'config.json');
}

export function getLocalConfigPath(root) {
  return join(root, CONFIG_DIR, 'config.local.json');
}

function safeReadJson(filePath) {
  try {
    const raw = JSON.parse(readFileSync(filePath, 'utf-8'));
    return raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : null;
  } catch {
    return null;
  }
}

function detectorSection(raw) {
  const section = raw && raw.detector;
  return section && typeof section === 'object' && !Array.isArray(section) ? section : null;
}

function uniqueStrings(values) {
  const seen = new Set();
  const out = [];
  for (const value of values || []) {
    if (typeof value !== 'string') continue;
    const trimmed = value.trim();
    if (!trimmed || seen.has(trimmed)) continue;
    seen.add(trimmed);
    out.push(trimmed);
  }
  return out;
}

function applySource(config, raw) {
  const section = detectorSection(raw);
  if (!section) return;
  for (const key of ['ignoreRules', 'ignoreFiles', 'ignoreValues']) {
    if (Array.isArray(section[key])) config[key].push(...section[key]);
  }
  if (section.designSystem && typeof section.designSystem === 'object') {
    config.designSystem = {
      ...config.designSystem,
      ...section.designSystem,
    };
  }
}

export function readDetectionConfig(root) {
  const config = {
    ignoreRules: [],
    ignoreFiles: [],
    ignoreValues: [],
    designSystem: { enabled: true },
    sources: [],
  };
  const shared = getConfigPath(root);
  const local = getLocalConfigPath(root);
  if (existsSync(shared)) {
    applySource(config, safeReadJson(shared));
    config.sources.push(shared);
  }
  if (existsSync(local)) {
    applySource(config, safeReadJson(local));
    config.sources.push(local);
  }
  for (const key of ['ignoreRules', 'ignoreFiles', 'ignoreValues']) {
    config[key] = uniqueStrings(config[key]);
  }
  return config;
}

/** Simple `**`-aware glob match against a POSIX-style relative path. */
export function matchesAnyGlob(filePath, globs) {
  if (!globs || !globs.length) return false;
  const normalized = filePath.split(sep).join('/');
  for (const glob of globs) {
    const pattern = String(glob).split(sep).join('/');
    const escaped = pattern
      .replace(/[.+^${}()|[\]\\]/g, '\\$&')
      .replace(/\*\*/g, '\u0000')
      .replace(/\*/g, '[^/]*')
      .replace(/\u0000/g, '.*');
    if (new RegExp(`^(?:.*/)?${escaped}$`).test(normalized)) return true;
  }
  return false;
}

export function shouldIgnoreDetectionFile(filePath, root, config) {
  if (!config || !config.ignoreFiles || !config.ignoreFiles.length) return false;
  let rel = filePath;
  try {
    rel = relative(resolve(root), resolve(filePath));
  } catch {
    /* keep original path */
  }
  return matchesAnyGlob(rel, config.ignoreFiles);
}

function findingRuleId(finding) {
  return finding?.antipattern || finding?.rule || finding?.id || '';
}

export function filterDetectionFindings(findings, config) {
  if (!config) return findings || [];
  const ignoreRules = new Set(config.ignoreRules || []);
  const ignoreValues = config.ignoreValues || [];
  const kept = [];
  for (const finding of findings || []) {
    if (ignoreRules.has(findingRuleId(finding))) continue;
    if (ignoreValues.length) {
      const haystack = `${finding?.snippet || ''} ${finding?.value || ''}`;
      if (ignoreValues.some(value => {
        const needle = String(value).includes(':')
          ? String(value).split(':').slice(1).join(':')
          : String(value);
        return needle && haystack.includes(needle);
      })) continue;
    }
    kept.push(finding);
  }
  return kept;
}
