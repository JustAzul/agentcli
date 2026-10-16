// Shared stubs for the mod tests: a fake world beneath the mod where the
// msgate engine interface, the agent registry and the display calls are all in
// memory.
import { mock } from 'claude-code/testing'

export type BackCall = { type: string; command: string; promptMode: string; model?: string; effort?: string; sandbox?: string }

// How the fake engine behaves: present with a version, absent altogether, or
// refusing the `backType` of the listed types.
export type Engine = { kind: 'absent' } | { kind: 'present'; version: string | (() => Promise<string>); refuse?: string[] }

export const present = (version = '1.0.0', refuse: string[] = []): Engine => ({ kind: 'present', version, refuse })
export const absent: Engine = { kind: 'absent' }

export type FlaggedRun = { run_id: string; purpose: string; source: string; started_at: string }
export type SpawnArgs = { subagentType: string; prompt: string; description: string }

export const RUN_TYPE = 'msgate-agents:run'
export const TYPES = ['adhoc', 'code-review', 'cross-check', 'delegation', 'expert-persona', 'second-opinion']
export const START = { surface: 'terminal', isInteractive: true, cwd: '/work' } as const
export const HANDOFF_FAILED = 'msgate: the hand-off to the agent failed, so this is not its answer.'

// world registers every stub a test needs. Call it before the first call on $.
export function world(on: any, engine: Engine = present()) {
  const w = {
    clock: mock.clock(on),
    toasts: [] as string[],
    debugLogs: [] as string[],
    agentTypes: [] as any[],
    backCalls: [] as BackCall[],
    versionCalls: 0,
    skillTexts: [] as string[],
    // The runs the engine reports as flagged, and what each spawn answers; a test sets them.
    flaggedCalls: 0,
    flaggedRuns: (async () => []) as () => Promise<FlaggedRun[]>,
    spawns: [] as SpawnArgs[],
    spawnAnswer: ((_args: SpawnArgs) => ({ model: 'haiku', agentId: 'row' })) as (args: SpawnArgs) => any,
  }
  on('session.start', () => ({ cwd: '/work' }))
  if (engine.kind === 'present') {
    on('engine.create', async (_$: any, e: any, next: any) => ({
      ...(await next(e)),
      msgate: {
        version: async () => {
          w.versionCalls += 1
          return typeof engine.version === 'function' ? engine.version() : engine.version
        },
        flaggedRuns: async () => {
          w.flaggedCalls += 1
          return w.flaggedRuns()
        },
        backType: async (args: BackCall) => {
          w.backCalls.push(args)
          if (engine.refuse?.includes(args.type)) throw new Error('msgate:backType:model')
          return { type: 'msgate-agents:' + args.type }
        },
      },
    }))
  }
  on('ui.toast', (_$: any, e: any) => {
    w.toasts.push(e.text)
    return { value: undefined }
  })
  on('ui.log', (_$: any, e: any) => {
    if (e.to === 'debug') w.debugLogs.push(e.text)
    return { value: undefined }
  })
  on('agent.register', (_$: any, e: any) => {
    w.agentTypes.push(e)
    return { value: { agent: 'msgate-agents:' + e.name } }
  })
  on('agent.spawn', (_$: any, e: any) => {
    w.spawns.push({ subagentType: e.subagentType, prompt: e.prompt, description: e.description })
    return w.spawnAnswer(w.spawns[w.spawns.length - 1])
  })
  on('agent.offer', () => ({ isOffered: true }))
  on('skill.prompt', (_$: any, e: any) => ({ text: e.text }))
  return w
}
