const SOURCE_UNKNOWN = 0;
const SOURCE_MOUSE = 1;
const SOURCE_TOUCHSCREEN = 2;

const TOOL_UNKNOWN = 0;
const TOOL_FINGER = 1;
const TOOL_PEN = 2;
const TOOL_MOUSE = 3;
const TOOL_TOUCHPAD = 4;

/**
 * Separates real touch from physical mouse input. ArkUI can synthesize both a
 * TouchEvent and a MouseEvent for one physical action, so callback names alone
 * are not enough to route input on API 23.
 */
export class InputEventGate {
  private lastTouchAt: number = 0;
  private readonly syntheticMouseGuardMs: number;

  constructor(syntheticMouseGuardMs: number = 320) {
    this.syntheticMouseGuardMs = syntheticMouseGuardMs;
  }

  shouldHandleTouch(source: number, sourceTool: number, now: number = Date.now()): boolean {
    if (source === SOURCE_MOUSE || sourceTool === TOOL_MOUSE || sourceTool === TOOL_TOUCHPAD) return false;
    this.lastTouchAt = now;
    return source === SOURCE_TOUCHSCREEN || sourceTool === TOOL_FINGER || sourceTool === TOOL_PEN ||
      (source === SOURCE_UNKNOWN && sourceTool === TOOL_UNKNOWN);
  }

  shouldHandleMouse(source: number, sourceTool: number, now: number = Date.now()): boolean {
    if (source === SOURCE_TOUCHSCREEN || sourceTool === TOOL_FINGER || sourceTool === TOOL_PEN) return false;
    if (source === SOURCE_MOUSE || sourceTool === TOOL_MOUSE || sourceTool === TOOL_TOUCHPAD) return true;
    return now - this.lastTouchAt > this.syntheticMouseGuardMs;
  }
}
