import { type Plugin, type PluginInput, tool } from '@opencode-ai/plugin'
import type { Event, Session } from '@opencode-ai/sdk/v2'
import { readFileSync, existsSync } from 'fs'

type BunShell = PluginInput['$']

// Focus tracking via file written by opencode-wrapper.ts
// The wrapper intercepts stdin focus events and writes state to this file
function getFocusFilePath(): string | null {
  // Check if wrapper set the env var
  if (process.env.OPENCODE_FOCUS_FILE) {
    return process.env.OPENCODE_FOCUS_FILE
  }

  // Fallback: try to find focus file by instance ID
  const instanceId =
    process.env.ZELLIJ_PANE_ID || process.env.NIRI_WINDOW_ID || null

  if (instanceId) {
    return `/tmp/opencode-focus-${instanceId}`
  }

  return null
}

function checkFocus(): boolean {
  const focusFile = getFocusFilePath()
  if (!focusFile) return true // Assume focused if no focus file

  try {
    if (!existsSync(focusFile)) return true // Assume focused if file doesn't exist
    const content = readFileSync(focusFile, 'utf-8').trim()
    return content === '1'
  } catch {
    return true // Assume focused on error
  }
}

function getInstanceId(): string {
  const zellijPane = process.env.ZELLIJ_PANE_ID
  const niriWindow = process.env.NIRI_WINDOW_ID

  if (zellijPane) return `zellij-${zellijPane}`
  if (niriWindow) return `niri-${niriWindow}`
  return `pid-${process.pid}`
}

function shortenPath(path: string): string {
  const home = process.env.HOME || ''
  let shortened = path.replace(new RegExp(`^${home}`), '~')

  const parts = shortened.split('/')
  if (parts.length <= 3) return shortened

  // Keep first part, abbreviate middle parts to first char, keep last two
  const result = [
    parts[0],
    ...parts.slice(1, -2).map((p) => (p ? p[0] : '')),
    ...parts.slice(-2),
  ]
  return result.join('/')
}

async function notify(
  $: BunShell,
  title: string,
  message: string,
): Promise<void> {
  // Skip if no display available
  if (!process.env.DISPLAY && !process.env.WAYLAND_DISPLAY) return

  const niriWindowId = process.env.NIRI_WINDOW_ID
  const zellijPaneId = process.env.ZELLIJ_PANE_ID

  const args = ['-t', '10000', '-a', 'OpenCode', '-i', 'Claude']

  if (niriWindowId) {
    args.push('--action=default=Focus Window')
  }

  args.push(title, message)

  try {
    const result = await $`notify-send ${args}`.text()
    const action = result.trim()

    if (action === 'default') {
      // Focus the window
      if (zellijPaneId) {
        await $`zellij pipe zellij-tools::focus-pane::${zellijPaneId}`.quiet()
      }

      if (niriWindowId) {
        const workspaces = await $`niri msg -j workspaces`.json()
        const windows = await $`niri msg -j windows`.json()

        const window = windows.find(
          (w: any) => w.id === parseInt(niriWindowId),
        )
        if (window) {
          const workspace = workspaces.find(
            (ws: any) => ws.id === window.workspace_id,
          )

          if (workspace?.name === '󰪷') {
            // If on scratchpad, move to focused monitor
            const focusedWorkspace = workspaces.find((ws: any) => ws.is_focused)
            if (focusedWorkspace) {
              await $`niri msg action move-window-to-monitor --id ${niriWindowId} ${focusedWorkspace.output}`.quiet()
            }
          }

          await $`niri msg action focus-window --id ${niriWindowId}`.quiet()
        }
      }
    }
  } catch {
    // Ignore notification errors
  }
}

export const NotificationPlugin: Plugin = async ({
  $,
  directory,
  project,
  client,
}) => {
  return {
    event: async ({ event: _event }) => {
      // Skip notifications if terminal is focused - user is already watching
      // Focus state is read from file written by opencode-wrapper.ts
      if (checkFocus()) return

      const event = _event as Event // use Event type from SDK v2

      let title = ''
      let message = ''

      switch (event.type) {
        case 'session.error':
          title = 'OpenCode Error'
          message = 'Session encountered an error'
          break

        case 'question.asked':
          title = 'OpenCode Question'
          message = event.properties.questions
            .map((q) => [`Q: ${q.question}`, q.options.map((o) => `   ${o.label}`)])
            .flat(2)
            .join('\n')
          break

        case 'permission.asked':
          title = 'OpenCode Permission'
          // TODO: extract permission details from event
          message = 'Permission requested'
          break

        // TODO: other events that require user notification

        default:
          return
      }

      // Prepend shortened path to title
      const shortPath = shortenPath(directory)
      title = `[${shortPath}] ${title}`

      await notify($, title, message)
    },
  }
}
