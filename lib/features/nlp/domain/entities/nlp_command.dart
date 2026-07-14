class NlpCommand {
  final String rawText;
  final String tokenizedText;
  final Map<String, String> tokenMap;
  final DateTime timestamp;

  NlpCommand({
    required this.rawText,
    required this.tokenizedText,
    required this.tokenMap,
    required this.timestamp,
  });

  factory NlpCommand.empty() {
    return NlpCommand(
      rawText: '',
      tokenizedText: '',
      tokenMap: {},
      timestamp: DateTime.now(),
    );
  }
}
