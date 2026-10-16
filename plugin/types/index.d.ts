// The msgate-agents plugin's contract: the values it keeps in the session's
// $.state. The engine interface it calls, `$.msgate` (`version()` and
// `backType()`), is added by the msgate engine plugin, not by this one, and is
// undefined when that plugin is not installed.

declare module 'claude-code' {
  interface PluginState {
    'msgate-agents': {
      // The dispatch skill has loaded in this session, so the agent types are
      // offered to the model.
      dispatchLoaded: boolean
      // The agent types the engine backed at this session's start: only these
      // are offered. Empty when the engine is missing or of another major.
      backedTypes: string[]
      // The session was already told the engine is missing, so a reload of the
      // plugin does not say it again.
      engineNoticeShown: boolean
    }
  }
}
