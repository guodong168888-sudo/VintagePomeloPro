import { display, window } from '@kit.ArkUI';
import { DeviceCapabilityPolicy } from './DeviceCapabilityPolicy';

// HDS MINI is rendered at 56 vp on phone/tablet shells (the tablet reports a
// 132 px title at 2.5 density). 40 vp is only the compact managed-window
// contract. Measuring the component repeatedly is unsafe because routed
// pages temporarily keep more than one HdsTitleBar alive.
export const HDS_MINI_TITLE_HEIGHT_VP: number = 56;
const MANAGED_HDS_MINI_TITLE_HEIGHT_VP: number = 40;
const STATUS_ONLY_SYSTEM_BARS: Array<'status' | 'navigation'> = ['status'];
const STATUS_ONLY_SYSTEM_BARS_KEY: string = STATUS_ONLY_SYSTEM_BARS.join(',');

interface WindowShellState {
  immersive: boolean;
  systemBarsKey: string;
}

// Routed pages share one EntryAbility window. Reapplying the same system-bar
// transaction at every push/pop produces extra avoidAreaChange passes on
// tablets. Cache the applied contract by the real window id, as
// VintagePomelo does, and only touch window chrome when the contract changed.
const windowShellStateCache: Map<number, WindowShellState> = new Map<number, WindowShellState>();

export interface StatusOnlyWindowInsets {
  top: number;
  left: number;
  right: number;
  bottom: number;
}

function usesImmersiveLibraryLayout(): boolean {
  // PC/2-in-1 keeps the system-managed title/decor area.  Making a routed
  // library page immersive there removes that area and then makes the page
  // compensate for it a second time.  Phones and tablets retain the HDS
  // immersive shell used by VintagePomelo.
  return !DeviceCapabilityPolicy.usesManagedWineWindows();
}

/**
 * Shared routed-page window contract. HDS MINI titles draw over the app
 * scene, so every library page must use the same status-only immersive shell.
 */
export async function applyStatusOnlyImmersiveShell(pageWindow: window.Window): Promise<void> {
  const immersive = usesImmersiveLibraryLayout();
  const properties = pageWindow.getWindowProperties();
  const cachedState = windowShellStateCache.get(properties.id);
  const layoutChanged = properties.isLayoutFullScreen !== immersive;
  const shellChanged = cachedState?.immersive !== immersive ||
    cachedState?.systemBarsKey !== (immersive ? STATUS_ONLY_SYSTEM_BARS_KEY : 'managed');
  if (layoutChanged) {
    await pageWindow.setWindowLayoutFullScreen(immersive);
  }
  if (!immersive) {
    // The normal PC/2-in-1 layout already reserves the system area.  Do not
    // change its navigation policy while returning from a routed page.
    if (layoutChanged || shellChanged) {
      try {
        await pageWindow.setSpecificSystemBarEnabled('status', true);
      } catch (_) {
      }
    }
    windowShellStateCache.set(properties.id, { immersive: false, systemBarsKey: 'managed' });
    return;
  }
  if (layoutChanged || shellChanged) {
    await pageWindow.setWindowSystemBarEnable(STATUS_ONLY_SYSTEM_BARS);
    try {
      await pageWindow.setSpecificSystemBarEnabled('status', true);
    } catch (_) {
    }
    try {
      await pageWindow.setSpecificSystemBarEnabled('navigationIndicator', false);
    } catch (_) {
    }
  }
  windowShellStateCache.set(properties.id,
    { immersive: true, systemBarsKey: STATUS_ONLY_SYSTEM_BARS_KEY });
}

/**
 * Read the current physical insets only when the page really owns an
 * immersive layout.  A normal PC/2-in-1 window already excludes the system
 * title area from its ArkUI layout; adding it again is the source of the
 * landscape blank band.
 */
export function getStatusOnlyWindowInsets(pageWindow: window.Window): StatusOnlyWindowInsets {
  const insets: StatusOnlyWindowInsets = { top: 0, left: 0, right: 0, bottom: 0 };
  try {
    if (!pageWindow.getWindowProperties().isLayoutFullScreen) {
      return insets;
    }
    const density = Math.max(1, display.getDefaultDisplaySync().densityPixels);
    const systemAvoid = pageWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    const cutoutAvoid = pageWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
    // 沉浸布局下系统导航指示条走独立的 TYPE_NAVIGATION_INDICATOR, 不并入
    // TYPE_SYSTEM; 漏掉它会让底部内容贴近手势条, 造成误触和导航图标不居中。
    const navigationAvoid = pageWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    insets.top = Math.ceil(Math.max(systemAvoid.topRect.height, cutoutAvoid.topRect.height) / density);
    insets.left = Math.ceil(Math.max(systemAvoid.leftRect.width, cutoutAvoid.leftRect.width) / density);
    insets.right = Math.ceil(Math.max(systemAvoid.rightRect.width, cutoutAvoid.rightRect.width) / density);
    insets.bottom = Math.ceil(Math.max(systemAvoid.bottomRect.height, cutoutAvoid.bottomRect.height,
      navigationAvoid.bottomRect.height) / density);
  } catch (_) {
  }
  return insets;
}

/** Content begins after the measured system inset and the HDS MINI title. */
export function getMiniTitleContentTopInset(pageWindow: window.Window): number {
  const titleHeight = usesImmersiveLibraryLayout() ?
    HDS_MINI_TITLE_HEIGHT_VP : MANAGED_HDS_MINI_TITLE_HEIGHT_VP;
  return titleHeight + getStatusOnlyWindowInsets(pageWindow).top;
}

/**
 * Keep routed pages in sync with rotation, system-bar visibility and the
 * return transition from settings/editors.  This is the same event-driven
 * pattern used by VintagePomelo's GameList, rather than a timed second read.
 */
export function observeStatusOnlyWindowInsets(
  pageWindow: window.Window,
  listener: (insets: StatusOnlyWindowInsets) => void,
): () => void {
  const refresh = (): void => {
    listener(getStatusOnlyWindowInsets(pageWindow));
  };
  const callback = (_data: window.AvoidAreaOptions): void => {
    refresh();
  };
  refresh();
  try {
    pageWindow.on('avoidAreaChange', callback);
  } catch (_) {
  }
  return (): void => {
    try {
      pageWindow.off('avoidAreaChange', callback);
    } catch (_) {
    }
  };
}
