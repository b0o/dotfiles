import { type Plugin, tool } from '@opencode-ai/plugin'
import type { AssistantMessage, Model } from '@opencode-ai/sdk'

// Thresholds: 25%, 50%, 75%, then every 5% until 95%, then every 1% until 100%
const THRESHOLDS = [25, 50, 75, 80, 85, 90, 95, 96, 97, 98, 99, 100]

// Track which thresholds have been alerted per session
const alertedThresholds = new Map<string, Set<number>>()

function getAlertedSet(sessionID: string): Set<number> {
  if (!alertedThresholds.has(sessionID)) {
    alertedThresholds.set(sessionID, new Set())
  }
  return alertedThresholds.get(sessionID)!
}

function findCrossedThreshold(
  percentage: number,
  alerted: Set<number>,
): number | null {
  // Find the highest threshold that has been crossed but not yet alerted
  for (let i = THRESHOLDS.length - 1; i >= 0; i--) {
    const threshold = THRESHOLDS[i]
    if (percentage >= threshold && !alerted.has(threshold)) {
      return threshold
    }
  }
  return null
}

export const LimitsPlugin: Plugin = async ({ client }) => {
  return {
    // Hook to inject context usage warnings into system prompt
    'experimental.chat.system.transform': async (
      input: { sessionID?: string; model: Model },
      output: { system: string[] },
    ) => {
      if (!input.sessionID) return

      const { sessionID, model } = input
      const contextLimit = model.limit.context

      if (!contextLimit) return

      // Fetch messages to get token usage
      const messagesRes = await client.session.messages({
        path: { id: sessionID },
      })

      if (messagesRes.error || !messagesRes.data) return

      const messages = messagesRes.data

      // Find last assistant message with output tokens
      let lastAssistant: AssistantMessage | undefined
      for (let i = messages.length - 1; i >= 0; i--) {
        const msg = messages[i].info
        if (msg.role === 'assistant' && msg.tokens.output > 0) {
          lastAssistant = msg as AssistantMessage
          break
        }
      }

      if (!lastAssistant) return

      // Calculate current usage
      const { tokens } = lastAssistant
      const totalTokens =
        tokens.input +
        tokens.output +
        tokens.reasoning +
        tokens.cache.read +
        tokens.cache.write

      const percentage = Math.round((totalTokens / contextLimit) * 100)

      // Check if we've crossed a new threshold
      const alerted = getAlertedSet(sessionID)
      const crossedThreshold = findCrossedThreshold(percentage, alerted)

      if (crossedThreshold !== null) {
        // Mark all thresholds up to this one as alerted
        for (const t of THRESHOLDS) {
          if (t <= crossedThreshold) {
            alerted.add(t)
          }
        }

        // Inject warning into system prompt
        const warning = [
          `<context-usage-warning>`,
          `You have used ${percentage}% of your context window.`,
          `Tokens used: ${totalTokens.toLocaleString()} / ${contextLimit.toLocaleString()}`,
          `Remaining: ~${(contextLimit - totalTokens).toLocaleString()} tokens`,
          percentage >= 90
            ? `CRITICAL: Context nearly exhausted. Finish current task or suggest continuing in a new session.`
            : percentage >= 75
              ? `WARNING: Consider wrapping up or summarizing progress soon.`
              : `INFO: Context checkpoint reached.`,
          `</context-usage-warning>`,
        ].join('\n')

        output.system.push(warning)
      }
    },

    tool: {
      checklimits: tool({
        args: {},
        description: "Check the current session's token usage limits",
        execute: async (_args, context) => {
          const { sessionID } = context

          // Get all messages for the session
          const messagesRes = await client.session.messages({
            path: { id: sessionID },
          })

          if (messagesRes.error || !messagesRes.data) {
            return `Error fetching messages: ${messagesRes.error}`
          }

          const messages = messagesRes.data

          // Find the last assistant message with output tokens > 0
          // This matches how the TUI sidebar calculates context usage
          let lastAssistant: AssistantMessage | undefined
          for (let i = messages.length - 1; i >= 0; i--) {
            const msg = messages[i].info
            if (msg.role === 'assistant' && msg.tokens.output > 0) {
              lastAssistant = msg as AssistantMessage
              break
            }
          }

          if (!lastAssistant) {
            return 'No assistant messages found'
          }

          // Get provider info to find model context limit
          const providersRes = await client.provider.list()

          if (providersRes.error || !providersRes.data) {
            return `Error fetching providers: ${providersRes.error}`
          }

          // Find the model's context limit
          let contextLimit = 0
          const provider = providersRes.data.all.find(
            (p) => p.id === lastAssistant!.providerID,
          )
          if (provider?.models?.[lastAssistant.modelID]) {
            contextLimit = provider.models[lastAssistant.modelID].limit.context
          }

          // Calculate total tokens from the LAST assistant message only
          // This is how the TUI calculates it - represents current context window usage
          const { tokens } = lastAssistant
          const totalTokens =
            tokens.input +
            tokens.output +
            tokens.reasoning +
            tokens.cache.read +
            tokens.cache.write

          const percentUsed =
            contextLimit > 0 ? Math.round((totalTokens / contextLimit) * 100) : 0

          // Also calculate cumulative cost across all messages
          let totalCost = 0
          for (const { info } of messages) {
            if (info.role === 'assistant') {
              totalCost += (info as AssistantMessage).cost
            }
          }

          const lines = [
            `Model: ${lastAssistant.providerID}/${lastAssistant.modelID}`,
            `Context Limit: ${contextLimit.toLocaleString()} tokens`,
            '',
            `Input: ${tokens.input.toLocaleString()}`,
            `Output: ${tokens.output.toLocaleString()}`,
            `Reasoning: ${tokens.reasoning.toLocaleString()}`,
            `Cache Read: ${tokens.cache.read.toLocaleString()}`,
            `Cache Write: ${tokens.cache.write.toLocaleString()}`,
            '',
            `Total: ${totalTokens.toLocaleString()} tokens`,
            `Context Used: ${percentUsed}%`,
            `Cost: $${totalCost.toFixed(2)}`,
          ]

          return lines.join('\n')
        },
      }),
    },
  }
}
