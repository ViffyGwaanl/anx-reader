enum AiDockSideEnum {
  left('left'),
  right('right');

  final String code;

  const AiDockSideEnum(this.code);

  static AiDockSideEnum fromCode(String code) {
    switch (code) {
      case 'left':
        return AiDockSideEnum.left;
      case 'right':
        return AiDockSideEnum.right;
      default:
        return AiDockSideEnum.right;
    }
  }
}
