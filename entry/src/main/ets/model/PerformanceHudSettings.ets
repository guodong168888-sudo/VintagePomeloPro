/** Display preferences only: never changes the graphics/guest launch environment. */
export interface PerformanceHudSettings {
  fps: boolean;
  appCpu: boolean;
  systemCpu: boolean;
  batteryTemperature: boolean;
  thermalLevel: boolean;
}

export type PerformanceHudField = 'fps' | 'appCpu' | 'systemCpu' | 'batteryTemperature' | 'thermalLevel';

export function normalizePerformanceHud(value?: PerformanceHudSettings): PerformanceHudSettings {
  return {
    fps: typeof value?.fps === 'boolean' ? value.fps : true,
    appCpu: value?.appCpu === true,
    systemCpu: value?.systemCpu === true,
    batteryTemperature: value?.batteryTemperature === true,
    thermalLevel: value?.thermalLevel === true
  };
}

export function hasPerformanceHudContent(value: PerformanceHudSettings): boolean {
  return value.fps || value.appCpu || value.systemCpu || value.batteryTemperature || value.thermalLevel;
}

export function hasPerformanceTelemetry(value: PerformanceHudSettings): boolean {
  return value.appCpu || value.systemCpu || value.batteryTemperature || value.thermalLevel;
}

export function setPerformanceHudField(current: PerformanceHudSettings,
  field: PerformanceHudField, enabled: boolean): PerformanceHudSettings {
  const next = normalizePerformanceHud(current);
  if (field === 'fps') next.fps = enabled;
  if (field === 'appCpu') next.appCpu = enabled;
  if (field === 'systemCpu') next.systemCpu = enabled;
  if (field === 'batteryTemperature') next.batteryTemperature = enabled;
  if (field === 'thermalLevel') next.thermalLevel = enabled;
  return next;
}
