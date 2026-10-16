import { expect, test } from 'claude-code/testing'
import { HANDOFF_FAILED, RUN_TYPE, START, TYPES, absent, present, world } from './kit'

test('session start registers the six agent types and backs each with its profile', async ($, on) => {
  const w = world(on)
  await $.session.start(START)

  expect(w.agentTypes.map((t) => t.name).sort()).toEqual([...TYPES].sort())
  for (const spec of w.agentTypes) {
    expect(spec.background).toBe(true)
    expect(spec.description).toContain('Use only when the user asks')
    expect(spec.model).toBe('haiku')
    expect(spec.tools).toEqual(['Read'])
    expect(spec.omitClaudeMd).toBe(true)
    expect(spec.prompt).toContain(HANDOFF_FAILED)
  }

  const byType = Object.fromEntries(w.backCalls.map((c) => [c.type, c]))
  expect(w.backCalls).toHaveLength(6)
  expect(byType['second-opinion']).toEqual({ type: 'second-opinion', command: 'exec', promptMode: 'free', model: 'gpt-6.1-sol', effort: 'high', sandbox: 'read-only' })
  expect(byType['code-review']).toEqual({ type: 'code-review', command: 'review', promptMode: 'review-target', model: 'gpt-6.1-sol', effort: 'high', sandbox: 'read-only' })
  expect(byType['cross-check']).toEqual({ type: 'cross-check', command: 'exec', promptMode: 'free', model: 'gpt-6.1-sol', effort: 'high', sandbox: 'read-only' })
  expect(byType['expert-persona']).toEqual({ type: 'expert-persona', command: 'exec', promptMode: 'free', model: 'gpt-6.1-sol', effort: 'xhigh', sandbox: 'read-only' })
  expect(byType['delegation']).toEqual({ type: 'delegation', command: 'exec', promptMode: 'free', model: 'gpt-6.1-sol', effort: 'medium', sandbox: 'workspace-write' })
  // adhoc leaves model and effort to the provider's defaults.
  expect(byType['adhoc']).toEqual({ type: 'adhoc', command: 'exec', promptMode: 'free', sandbox: 'read-only' })
})

const offer = ($: any, agent: string) => $.agent.offer({ agent, description: '', source: 'plugin', provider: { plugin: 'msgate-agents', tier: 'user' } } as any)

test('the agent types are hidden from the model until the dispatch skill loads in the session', async ($, on) => {
  world(on)
  await $.session.start(START)

  expect(await offer($, 'msgate-agents:delegation')).toEqual({ isOffered: false })
  // Agents of other plugins and the built-in ones are never this plugin's to hide.
  expect(await offer($, 'Explore')).toEqual({ isOffered: true })

  await $.skill.prompt({ skill: 'msgate-agents:other', text: '' })
  expect(await offer($, 'msgate-agents:delegation')).toEqual({ isOffered: false })

  await $.skill.prompt({ skill: 'msgate-agents:dispatch', text: 'Dispatch' })
  for (const name of TYPES) expect(await offer($, 'msgate-agents:' + name)).toEqual({ isOffered: true })
})

const loadDispatch = ($: any) => $.skill.prompt({ skill: 'msgate-agents:dispatch', text: 'Dispatch' })
const NEEDS = 'msgate-agents needs the msgate engine plugin 1.x'

test('with no engine installed the session shows one toast and one log line and offers no type', async ($, on) => {
  const w = world(on, absent)
  await $.session.start(START)
  await loadDispatch($)

  expect(w.toasts).toEqual([NEEDS])
  expect(w.debugLogs.filter((line) => line.includes('msgate engine'))).toHaveLength(1)
  expect(w.backCalls).toEqual([])
  for (const name of TYPES) expect(await offer($, 'msgate-agents:' + name)).toEqual({ isOffered: false })
})

test('an engine of another major shows one toast naming 1.x and the version found, backs nothing and hides every type', async ($, on) => {
  const w = world(on, present('2.0.0'))
  await $.session.start(START)
  await loadDispatch($)

  expect(w.toasts).toHaveLength(1)
  expect(w.toasts[0]).toContain(NEEDS)
  expect(w.toasts[0]).toContain('2.0.0')
  expect(w.backCalls).toEqual([])
  for (const name of TYPES) expect(await offer($, 'msgate-agents:' + name)).toEqual({ isOffered: false })
})

test('an engine whose version call is refused is treated as missing', async ($, on) => {
  const w = world(on, present(async () => {
    throw new Error('msgate:version:unserved')
  }))
  await $.session.start(START)
  await loadDispatch($)

  expect(w.toasts).toEqual([NEEDS])
  expect(w.backCalls).toEqual([])
  expect(await offer($, 'msgate-agents:adhoc')).toEqual({ isOffered: false })
})

test('a reload of a session that already heard the engine is missing shows no second toast', async ($, on) => {
  const w = world(on, absent)
  await $.session.start(START)
  await $.session.start(START)

  expect(w.toasts).toEqual([NEEDS])
})

test('when the engine refuses one type that type is hidden and logged, and the other five are offered', async ($, on) => {
  const w = world(on, present('1.4.2', ['delegation']))
  await $.session.start(START)
  await loadDispatch($)

  expect(await offer($, 'msgate-agents:delegation')).toEqual({ isOffered: false })
  for (const name of TYPES.filter((type) => type !== 'delegation')) expect(await offer($, 'msgate-agents:' + name)).toEqual({ isOffered: true })
  expect(w.debugLogs.filter((line) => line.includes('delegation') && line.includes('msgate:backType:model'))).toHaveLength(1)
  expect(w.toasts).toEqual([])
})

test('every session start backs the six types again, and the dispatch gate survives the reload', async ($, on) => {
  const w = world(on)
  await $.session.start(START)
  await loadDispatch($)
  await $.session.start(START)

  expect(w.backCalls).toHaveLength(12)
  expect(w.backCalls.slice(6).map((call) => call.type).sort()).toEqual([...TYPES].sort())
  expect(await offer($, 'msgate-agents:adhoc')).toEqual({ isOffered: true })
})

const runRegistered = (w: any) => w.agentTypes.filter((t: any) => t.name === 'run')
const runBacked = (w: any) => w.backCalls.filter((c: any) => c.type === 'run')

test('an engine from 1.1 on gets the hidden run type, registered with no tools and backed to follow a run id', async ($, on) => {
  const w = world(on, present('1.1.0'))
  await $.session.start(START)

  expect(runRegistered(w)).toHaveLength(1)
  expect(runRegistered(w)[0].tools).toEqual([])
  expect(runBacked(w)).toEqual([{ type: 'run', command: 'follow', promptMode: 'run-id' }])
  // The six dispatchable types are untouched by it.
  expect(w.backCalls.filter((c: any) => c.type !== 'run')).toHaveLength(6)
})

test('a later minor or patch of 1.x keeps the hidden run type', async ($, on) => {
  const w = world(on, present('1.12.3'))
  await $.session.start(START)

  expect(runRegistered(w)).toHaveLength(1)
  expect(runBacked(w)).toHaveLength(1)
})

test('an engine at 1.0.x gets no hidden run type and no timer, and the six types stay as they were', async ($, on) => {
  const w = world(on, present('1.0.9'))
  w.flaggedRuns = async () => [{ run_id: 'r1', purpose: 'second-opinion', source: 'cli', started_at: '' }]
  await $.session.start(START)
  await w.clock.advance(20000)

  expect(runRegistered(w)).toEqual([])
  expect(runBacked(w)).toEqual([])
  expect(w.backCalls).toHaveLength(6)
  expect(w.flaggedCalls).toBe(0)
  expect(w.spawns).toEqual([])
})

test('the hidden run type is offered to no model, with the dispatch skill loaded or not', async ($, on) => {
  world(on, present('1.1.0'))
  await $.session.start(START)

  expect(await offer($, RUN_TYPE)).toEqual({ isOffered: false })
  await loadDispatch($)
  expect(await offer($, RUN_TYPE)).toEqual({ isOffered: false })
  // The dispatchable types it sits beside are still offered.
  expect(await offer($, 'msgate-agents:adhoc')).toEqual({ isOffered: true })
})

test('the hidden run type stays refused when the engine is missing or too old', async ($, on) => {
  world(on, absent)
  await $.session.start(START)
  await loadDispatch($)

  expect(await offer($, RUN_TYPE)).toEqual({ isOffered: false })
})
