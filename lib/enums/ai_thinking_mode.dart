enum AiThinkingMode {
  off,
  auto,
  minimal,
  low,
  medium,
  high,
}

AiThinkingMode aiThinkingModeFromString(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'auto':
      return AiThinkingMode.auto;
    case 'minimal':
      return AiThinkingMode.minimal;
    case 'low':
      return AiThinkingMode.low;
    case 'medium':
      return AiThinkingMode.medium;
    case 'high':
      return AiThinkingMode.high;
    case 'off':
    default:
      return AiThinkingMode.off;
  }
}

String aiThinkingModeToString(AiThinkingMode mode) {
  switch (mode) {
    case AiThinkingMode.off:
      return 'off';
    case AiThinkingMode.auto:
      return 'auto';
    case AiThinkingMode.minimal:
      return 'minimal';
    case AiThinkingMode.low:
      return 'low';
    case AiThinkingMode.medium:
      return 'medium';
    case AiThinkingMode.high:
      return 'high';
  }
}
