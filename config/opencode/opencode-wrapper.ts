#!/usr/bin/env bun
/**
 * Wrapper for opencode that creates a PTY and intercepts focus events.
 * Acts like a mini terminal multiplexer - sits between the real terminal and opencode.
 *
 * Usage: bun opencode-wrapper.ts [opencode args...]
 */

import { spawn } from 'bun'
import { writeFileSync, unlinkSync } from 'fs'

const FOCUS_IN = '\x1b[I'
const FOCUS_OUT = '\x1b[O'
const ENABLE_FOCUS_REPORTING = '\x1b[?1004h'
const DISABLE_FOCUS_REPORTING = '\x1b[?1004l'

// Get our Niri window ID - either from env or by querying the focused window
async function getNiriWindowId(): Promise<number | null> {
  if (process.env.NIRI_WINDOW_ID) {
    return parseInt(process.env.NIRI_WINDOW_ID)
  }

  // Query Niri for the currently focused window (which should be us at startup)
  try {
    const proc = Bun.spawn(['niri', 'msg', '-j', 'focused-window'], {
      stdout: 'pipe',
      stderr: 'ignore',
    })
    const output = await new Response(proc.stdout).text()
    const window = JSON.parse(output)
    return window?.id ?? null
  } catch {
    return null
  }
}

const niriWindowId = await getNiriWindowId()

// Instance identifier for the focus file
const instanceId =
  process.env.ZELLIJ_PANE_ID || String(niriWindowId) || String(process.pid)
const focusFile = `/tmp/opencode-focus-${instanceId}`

// Track current focus state to avoid duplicate notifications
let currentFocusState = true

// DEBUG: Send desktop notification on focus change
function debugNotify(message: string): void {
  spawn(['notify-send', '-t', '2000', '-a', 'OpenCode Wrapper', 'Focus Debug', message])
}

function writeFocusState(focused: boolean, source: string): void {
  // Avoid duplicate state changes
  if (focused === currentFocusState) return
  currentFocusState = focused

  writeFileSync(focusFile, focused ? '1' : '0')
  // DEBUG: Notify on focus change
  debugNotify(`${focused ? 'FOCUSED' : 'UNFOCUSED'} (${source})`)
}

// Listen to Niri events for window focus changes
let niriEventProc: ReturnType<typeof spawn> | null = null

function startNiriEventListener(): void {
  if (!niriWindowId) {
    debugNotify('No NIRI_WINDOW_ID')
    return
  }

  debugNotify(`Starting niri listener for window ${niriWindowId}`)

  niriEventProc = spawn(['niri', 'msg', '-j', 'event-stream'], {
    stdout: 'pipe',
    stderr: 'ignore',
  })

  const reader = niriEventProc.stdout.getReader()
  const decoder = new TextDecoder()
  let buffer = ''

  ;(async () => {
    while (true) {
      const { done, value } = await reader.read()
      if (done) {
        debugNotify('Niri event stream ended')
        break
      }

      buffer += decoder.decode(value, { stream: true })

      // Process complete lines
      const lines = buffer.split('\n')
      buffer = lines.pop() || '' // Keep incomplete line in buffer

      for (const line of lines) {
        if (!line.trim()) continue

        try {
          const event = JSON.parse(line)

          // WindowFocusChanged event tells us which window is now focused
          if (event.WindowFocusChanged !== undefined) {
            const focusedId = event.WindowFocusChanged?.id ?? null
            // DEBUG: Log focus change
            debugNotify(`Niri focus: ${focusedId} (ours: ${niriWindowId})`)
            if (focusedId === niriWindowId) {
              writeFocusState(true, 'niri')
            } else {
              writeFocusState(false, 'niri')
            }
          }
        } catch {
          // Ignore parse errors
        }
      }
    }
  })()
}

function cleanup(): void {
  process.stdout.write(DISABLE_FOCUS_REPORTING)
  // Kill Niri event listener
  niriEventProc?.kill()
  try {
    unlinkSync(focusFile)
  } catch {}
}

// Get terminal size
const rows = process.stdout.rows || 24
const cols = process.stdout.columns || 80

// Initialize focus state
currentFocusState = true
writeFileSync(focusFile, '1')

// Enable focus reporting on the real terminal
process.stdout.write(ENABLE_FOCUS_REPORTING)

// Start Niri event listener for window-level focus
startNiriEventListener()

// Spawn opencode with a PTY using Bun's terminal option
const args = process.argv.slice(2)
const proc = spawn(['opencode', ...args], {
  env: {
    ...process.env,
    OPENCODE_FOCUS_FILE: focusFile,
    TERM: process.env.TERM || 'xterm-256color',
    COLORTERM: process.env.COLORTERM || 'truecolor',
  },
  terminal: {
    rows,
    cols,
    // Called when data is received from opencode's terminal
    data(terminal, data) {
      // Forward output to real terminal
      process.stdout.write(data)
    },
  },
})

// Handle cleanup
process.on('exit', cleanup)
process.on('SIGINT', () => {
  proc.kill('SIGINT')
})
process.on('SIGTERM', () => {
  proc.kill('SIGTERM')
})

// Handle terminal resize - forward to the PTY
process.stdout.on('resize', () => {
  const newRows = process.stdout.rows || 24
  const newCols = process.stdout.columns || 80
  // Bun's terminal supports resize
  proc.terminal?.resize?.(newCols, newRows)
})

// Set raw mode on our stdin so we get individual keypresses
if (process.stdin.isTTY) {
  process.stdin.setRawMode(true)
}
process.stdin.resume()

// Forward stdin to opencode's PTY, intercepting focus events
process.stdin.on('data', (data: Buffer) => {
  const str = data.toString()

  // Detect focus sequences from terminal
  if (str.includes(FOCUS_IN)) {
    writeFocusState(true, 'terminal')
  }
  if (str.includes(FOCUS_OUT)) {
    writeFocusState(false, 'terminal')
  }

  // Forward all input to opencode's terminal
  proc.terminal?.write(data)
})

// Wait for opencode to exit
const exitCode = await proc.exited

// Cleanup
proc.terminal?.close()
cleanup()
process.exit(exitCode)
