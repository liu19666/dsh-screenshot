// tools/plugin-smoke.mjs is the single implementation of the plugin smoke test (see
// docs/VERIFY.md). This entry point is kept because older docs and task descriptions call
// it by path: it resolves the repository root from its own URL, so it no longer depends on
// the working directory, and then runs the real implementation.
import { spawnSync } from 'node:child_process'
import { join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = fileURLToPath(new URL('.', import.meta.url))
const repoRoot = resolve(here, '..', '..')
const tool = join(repoRoot, 'tools', 'plugin-smoke.mjs')

console.log('[smoke] delegating to tools/plugin-smoke.mjs (single implementation)')
const run = spawnSync(process.execPath, [tool, '--root', repoRoot, ...process.argv.slice(2)], { stdio: 'inherit' })
if (run.error) {
  console.error('[smoke] could not run tools/plugin-smoke.mjs: ' + String(run.error.message || run.error))
  process.exit(1)
}
process.exit(typeof run.status === 'number' ? run.status : 1)
