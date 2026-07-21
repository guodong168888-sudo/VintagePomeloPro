@Component
export struct AppSearchBar {
  @Prop value: string = '';
  placeholder: string = '搜索 Windows 应用';
  onValueChange: (value: string) => void = (_value: string): void => {};

  build() {
    Search({ value: this.value, placeholder: this.placeholder })
      .height(48)
      .width('100%')
      .backgroundColor($r('app.color.search_background'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .borderRadius(24)
      .padding({ left: 6, right: 6 })
      .onChange((value: string) => this.onValueChange(value))
  }
}
