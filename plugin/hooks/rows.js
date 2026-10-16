// The hidden `run` type and the rows it opens. Nothing here runs a model: the
// engine answers each row, and the type is offered to no model.
import { RUN_TYPE, hasRunRows, runBackArgs, runSpec } from './agents.js'

const POLL_MS = 5000

function messageOf(error) {
  return String(error && error.message ? error.message : error)
}

// openRunRows backs the hidden type with the engine and registers it, only
// when the engine can serve it. It returns whether the rows can be opened.
async function openRunRows($, version) {
  if (!hasRunRows(version)) return false
  try {
    await $.msgate.backType(runBackArgs())
    await $.agent.register(runSpec())
    return true
  } catch (error) {
    $.ui.log('msgate-agents: the hidden run type is not available: ' + messageOf(error), { to: 'debug' })
    return false
  }
}

// openRow opens the row of one run. A refusal or a failure is one log line for
// the run: the run has been marked tried before, so it is not asked again.
async function openRow($, run) {
  try {
    const result = await $.agent.spawn({
      subagentType: $.plugin.name + ':' + RUN_TYPE,
      prompt: 'msgate run ' + run.run_id,
      description: run.purpose + ' · ' + run.source,
    })
    if (result.deny !== undefined) logRefused($, run, result.deny)
  } catch (error) {
    logRefused($, run, messageOf(error))
  }
}

function logRefused($, run, reason) {
  $.ui.log('msgate-agents: no row opened for run ' + run.run_id + ': ' + reason, { to: 'debug' })
}

async function openNewRows($) {
  for (const run of await $.msgate.flaggedRuns()) {
    if (tried.has(run.run_id)) continue
    tried.add(run.run_id)
    await openRow($, run)
  }
}

// The runs already tried in this load of the plugin, and the timer that polls
// for new ones. A run is tried once: the engine stops listing a run once it
// has a row, and a refused run is not asked again.
const tried = new Set()
let timer = null
let isPolling = false
let lastListFailure = null

// poll lists the flagged runs and opens their rows. A period that comes while
// the last poll is still running does nothing, so polls never overlap. A
// failed listing is logged when its reason changes, not on every period.
async function poll($) {
  if (isPolling) return
  isPolling = true
  try {
    await openNewRows($)
    lastListFailure = null
  } catch (error) {
    const reason = messageOf(error)
    if (reason !== lastListFailure) $.ui.log('msgate-agents: could not list the flagged runs: ' + reason, { to: 'debug' })
    lastListFailure = reason
  } finally {
    isPolling = false
  }
}

// stopRunRows ends the poll, for an engine that cannot serve the hidden type.
export function stopRunRows() {
  if (timer !== null) timer.cancel()
  timer = null
}

// startRunRows backs and registers the hidden type, and polls for flagged runs
// on a timer of the plugin's own, only when the engine can serve the type.
export async function startRunRows($, version) {
  stopRunRows()
  if (!(await openRunRows($, version))) return
  timer = $.clock.every(POLL_MS, () => {
    poll($)
  })
}
