import deviceInfo from '@ohos.deviceInfo';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;

export class DeviceCapabilityPolicy {
  static deviceType(): string {
    return deviceInfo.deviceType;
  }

  static isPhoneDevice(): boolean {
    return DeviceCapabilityPolicy.deviceType() === 'phone';
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
}
