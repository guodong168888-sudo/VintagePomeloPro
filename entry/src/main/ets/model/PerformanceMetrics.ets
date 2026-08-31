export interface ProcessCpuTicks {
  pid: number;
  startTicks: number;
  cpuTicks: number;
}
export interface CpuSnapshot {
  timestampMs: number;
  ticksPerSecond: number;
  appReadable: boolean;
  appPartial: boolean;
  systemReadable: boolean;
  systemPercent: number;
  systemTotal: number;
  systemIdle: number;
  processes: ProcessCpuTicks[];
}
export interface CpuUsage {
  app: number | null;
  system: number | null;
  partial: boolean;
}

/** 100% app CPU = one logical core; system CPU is normalized across all cores. */
export function calculateCpuUsage(previous: CpuSnapshot | null, current: CpuSnapshot): CpuUsage {
  const result: CpuUsage = { app: null, system: null, partial: current.appPartial };
  if (Number.isFinite(current.systemPercent) && current.systemPercent > 0 && current.systemPercent <= 100) {
    result.system = current.systemPercent;
  }
  if (!previous) return result;
  const elapsedMs = current.timestampMs - previous.timestampMs;
  // Resume/stale samples must establish a new baseline, not smear background time.
  if (!Number.isFinite(elapsedMs) || elapsedMs < 250 || elapsedMs > 10000) return result;
  if (current.systemReadable && previous.systemReadable) {
    const total = current.systemTotal - previous.systemTotal;
    const idle = current.systemIdle - previous.systemIdle;
    if (Number.isFinite(total) && total > 0 && idle >= 0 && idle <= total) {
      result.system = 100 * (total - idle) / total;
    }
  }
  if (!current.appReadable || !previous.appReadable || current.ticksPerSecond <= 0 ||
    current.ticksPerSecond !== previous.ticksPerSecond) return result;
  const before = new Map<number, ProcessCpuTicks>();
  previous.processes.forEach((value: ProcessCpuTicks): void => { before.set(value.pid, value); });
  let ticks = 0;
  let matched = 0;
  result.partial = result.partial || previous.appPartial;
  current.processes.forEach((value: ProcessCpuTicks): void => {
    const old = before.get(value.pid);
    if (!old || old.startTicks !== value.startTicks || value.cpuTicks < old.cpuTicks) {
      result.partial = true; // Birth, PID reuse or denied reads are not zero CPU.
      return;
    }
    ticks += value.cpuTicks - old.cpuTicks;
    matched++;
  });
  if (matched < previous.processes.length) result.partial = true;
  const percent = ticks * 100000 / (elapsedMs * current.ticksPerSecond);
  if (matched > 0 && Number.isFinite(percent) && percent >= 0) result.app = percent;
  return result;
}

export function formatCpuPercent(value: number | null, partial: boolean = false): string {
  return value === null || !Number.isFinite(value) ? '不可用' :
    (partial ? '≥' : '') + value.toFixed(0) + '%';
}

export function formatBatteryTemperature(tenthsCelsius: number): string {
  // batteryInfo uses 0.1°C, not ThermalService's milli-degree diagnostics.
  return Number.isFinite(tenthsCelsius) && tenthsCelsius >= -400 && tenthsCelsius <= 1000 ?
    (tenthsCelsius / 10).toFixed(1) + '℃' : '不可用';
}

export function formatThermalLevel(level: number): string {
  const names: string[] = ['凉爽', '正常', '温热', '发热', '过热', '警告', '紧急', '逃生'];
  return Number.isInteger(level) && level >= 0 && level < names.length ?
    names[level] + ' (' + level.toString() + ')' : '不可用';
}
