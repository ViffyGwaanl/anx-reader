enum AiPadPanelModeEnum {
  dock('dock'),
  bottomSheet('bottomSheet');

  final String code;

  const AiPadPanelModeEnum(this.code);

  static AiPadPanelModeEnum fromCode(String code) {
    switch (code) {
      case 'dock':
        return AiPadPanelModeEnum.dock;
      case 'bottomSheet':
        return AiPadPanelModeEnum.bottomSheet;
      default:
        return AiPadPanelModeEnum.dock;
    }
  }
}
