/**
 * 本地声明：系统分享面板（ShareKit）。
 *
 * 当前构建 SDK 是 OpenHarmony 公共 SDK，未附带 @kit.ShareKit；
 * 真机为 HarmonyOS NEXT，运行时自带该 kit。这里提供最小声明让
 * ArkTS 编译通过，运行时不依赖 SDK 元数据。
 */
declare module '@kit.ShareKit' {
  namespace systemShare {
    enum SelectionMode {
      SINGLE = 0,
      MULTIPLE = 1
    }

    enum SharePreviewMode {
      DETAIL = 0,
      LIST = 1
    }

    interface ShareOptions {
      selectionMode?: SelectionMode;
      previewMode?: SharePreviewMode;
    }

    interface SharedDataOptions {
      utd: string;
      uri?: string;
      content?: string;
      title?: string;
      description?: string;
      thumbnailUri?: string;
    }

    class SharedData {
      constructor(options: SharedDataOptions);
    }

    class ShareController {
      constructor(data: SharedData);
      show(context: Object, options?: ShareOptions): Promise<void>;
    }
  }

  export { systemShare };
}
