// Registers Gemini as an ACP provider in Paseo's config (Paseo has no built-in Gemini).
// Only adds it when missing, so your own edits stay. Works on Windows (%USERPROFILE%\.paseo) and Linux.
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const home = process.env.PASEO_HOME || path.join(os.homedir(), '.paseo')
const file = path.join(home, 'config.json')
let config = {}
try {
  config = JSON.parse(fs.readFileSync(file, 'utf8'))
} catch (e) {
  if (e.code !== 'ENOENT') {
    console.error(`[setup] ${file} 를 읽을 수 없어 건드리지 않았어요: ${e.message}`)
    process.exit(0)
  }
}
config.agents ??= {}
config.agents.providers ??= {}
if (config.agents.providers.gemini) {
  console.log(`[setup] Gemini 이미 등록됨 (${file})`)
} else {
  config.agents.providers.gemini = { extends: 'acp', label: 'Gemini', command: ['gemini', '--acp'] }
  fs.mkdirSync(home, { recursive: true })
  fs.writeFileSync(file, JSON.stringify(config, null, 2) + '\n')
  console.log(`[setup] Gemini(ACP)를 ${file} 에 등록했어요. Paseo를 다시 시작하거나 'paseo daemon reload' 하세요.`)
}
