// The hidden `run` type and the rows it opens. Nothing here runs a model: the
// engine answers each row, and the type is offered to no model.
import { hasRunRows, runBackArgs, runSpec } from './agents.js'

function messageOf(error) {
  return String(error && error.message ? error.message : error)
}

// openRunRows backs the hidden type with the engine and registers it, only
// when the engine can serve it. It returns whether the rows can be opened.
export async function openRunRows($, version) {
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
