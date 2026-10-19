// Prefer a local install; otherwise reuse the same bundled runtime without a project junction.
import { createRequire } from 'node:module';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const local = createRequire(import.meta.url);
let entry;
try {
  entry = local.resolve('@oai/artifact-tool');
} catch (error) {
  if (error.code !== 'MODULE_NOT_FOUND') throw error;
  const modules = process.env.CODEX_WORKSPACE_NODE_MODULES
    || join(homedir(), '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules');
  const bundled = createRequire(join(modules, '.artifact-runtime-loader.cjs'));
  try {
    entry = bundled.resolve('@oai/artifact-tool');
  } catch (cause) {
    throw new Error('找不到表格运行时。请设置 CODEX_WORKSPACE_NODE_MODULES，或恢复本目录的 node_modules。', { cause });
  }
}
export const { Workbook, SpreadsheetFile } = await import(pathToFileURL(entry).href);
