import deviceInfo from '@ohos.deviceInfo';
import { window } from '@kit.ArkUI';
import { hilog } from '../service/LogService';
import { ScreenOrientationSetting } from '../model/AppModels';

const DOMAIN = 0x0000;

export class DeviceCapabilityPolicy {
  static deviceType(): string {
    return deviceInfo.deviceType;
  }

  static isPhoneDevice(): boolean {
    return DeviceCapabilityPolicy.deviceType() === 'phone';
  }

  static isTabletDevice(): boolean {
    return DeviceCapabilityPolicy.deviceType() === 'tablet';
  }

  static usesForkNativeChildProcess(): boolean {
    const type = DeviceCapabilityPolicy.deviceType();
    return type === 'phone' || type === 'tv';
  }

  static usesManagedWineWindows(): boolean {
    const type = DeviceCapabilityPolicy.deviceType();
    return type === '2in1' || type === 'pc';
  }

  static supportsSensorRotation(): boolean {
    return DeviceCapabilityPolicy.isPhoneDevice();
  }

  static enableSensorRotation(target: window.Window, tag: string): void {
    if (!DeviceCapabilityPolicy.supportsSensorRotation()) return;
    target.setPreferredOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED).then(() => {
      hilog.info(DOMAIN, tag, 'Phone auto rotation enabled');
    }).catch((error: Error) => {
      hilog.warn(DOMAIN, tag, 'Phone auto rotation unavailable: %{public}s', JSON.stringify(error));
    });
  }

  static applyDesktopOrientation(target: window.Window, setting: ScreenOrientationSetting, tag: string): Promise<void> {
    let orientation: window.Orientation = window.Orientation.AUTO_ROTATION_LANDSCAPE_RESTRICTED;
    if (setting === ScreenOrientationSetting.LANDSCAPE) {
      orientation = window.Orientation.LANDSCAPE;
    } else if (setting === ScreenOrientationSetting.PORTRAIT) {
      orientation = window.Orientation.PORTRAIT;
    }
    return target.setPreferredOrientation(orientation).then(() => {
      hilog.info(DOMAIN, tag, 'Desktop orientation applied: %{public}s', setting);
    }).catch((error: Error) => {
      hilog.warn(DOMAIN, tag, 'Desktop orientation unavailable: %{public}s', JSON.stringify(error));
    });
  }
}
