import { display, window } from '@kit.ArkUI';

const MINI_TITLE_BAR_HEIGHT_VP: number = 56;
const CONTENT_GAP_BELOW_TITLE_VP: number = 16;
const STATUS_ONLY_SYSTEM_BARS: Array<'status' | 'navigation'> = ['status'];

/**
 * Shared routed-page window contract. HDS MINI titles draw over the app
 * scene, so every library page must use the same status-only immersive shell.
 */
export async function applyStatusOnlyImmersiveShell(pageWindow: window.Window): Promise<void> {
  if (!pageWindow.getWindowProperties().isLayoutFullScreen) {
    await pageWindow.setWindowLayoutFullScreen(true);
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

/** Content begins after the measured status bar, HDS MINI title, and 16vp gap. */
export function getMiniTitleContentTopInset(pageWindow: window.Window): number {
  let statusBarHeightVp = 0;
  try {
    const systemAvoid = pageWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    const cutoutAvoid = pageWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
    const topPx = Math.max(systemAvoid.topRect.height, cutoutAvoid.topRect.height);
    const density = Math.max(1, display.getDefaultDisplaySync().densityPixels);
    statusBarHeightVp = Math.ceil(topPx / density);
  } catch (_) {
  }
  return MINI_TITLE_BAR_HEIGHT_VP + statusBarHeightVp + CONTENT_GAP_BELOW_TITLE_VP;
}
