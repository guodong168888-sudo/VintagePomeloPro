import { display, window } from '@kit.ArkUI';
import { DeviceCapabilityPolicy } from './DeviceCapabilityPolicy';

// HDS MINI's actual visual title height.  Do not add an arbitrary gap here:
// the page-specific cards already own their own outer spacing.
export const HDS_MINI_TITLE_HEIGHT_VP: number = 40;
const STATUS_ONLY_SYSTEM_BARS: Array<'status' | 'navigation'> = ['status'];

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
  if (pageWindow.getWindowProperties().isLayoutFullScreen !== immersive) {
    await pageWindow.setWindowLayoutFullScreen(immersive);
  }
  if (!immersive) {
    // The normal PC/2-in-1 layout already reserves the system area.  Do not
    // change its navigation policy while returning from a routed page.
    try {
      await pageWindow.setSpecificSystemBarEnabled('status', true);
    } catch (_) {
    }
    return;
  }
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
    insets.top = Math.ceil(Math.max(systemAvoid.topRect.height, cutoutAvoid.topRect.height) / density);
    insets.left = Math.ceil(Math.max(systemAvoid.leftRect.width, cutoutAvoid.leftRect.width) / density);
    insets.right = Math.ceil(Math.max(systemAvoid.rightRect.width, cutoutAvoid.rightRect.width) / density);
    insets.bottom = Math.ceil(Math.max(systemAvoid.bottomRect.height, cutoutAvoid.bottomRect.height) / density);
  } catch (_) {
  }
  return insets;
}

/** Content begins after the measured system inset and the HDS MINI title. */
export function getMiniTitleContentTopInset(pageWindow: window.Window): number {
  return HDS_MINI_TITLE_HEIGHT_VP + getStatusOnlyWindowInsets(pageWindow).top;
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
