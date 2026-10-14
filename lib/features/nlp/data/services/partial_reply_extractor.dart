/// Gemini는 `responseMimeType: application/json`으로 스트리밍하므로
/// 토큰 청크는 `{"intent":"CREATE_EVENT","aiReplyMessage":"내일 3시에...` 같은
/// **미완성 JSON 조각**이다. 사용자에게 raw JSON을 보여줄 수 없으므로,
/// 누적된 JSON 문자열에서 `aiReplyMessage` 값만 (미완성이어도) 추출한다.
class PartialReplyExtractor {
  static final _keyPattern = RegExp(r'"aiReplyMessage"\s*:\s*"');

  final StringBuffer _raw = StringBuffer();
  String _lastReply = '';

  /// 지금까지 추출된 답변 텍스트.
  String get reply => _lastReply;

  /// 새 JSON 조각을 누적하고, 직전 대비 **새로 늘어난 답변 텍스트(delta)**를 반환.
  /// 아직 `aiReplyMessage`가 시작되지 않았으면 빈 문자열.
  String add(String jsonFragment) {
    _raw.write(jsonFragment);
    final current = extract(_raw.toString());
    if (current.length <= _lastReply.length || !current.startsWith(_lastReply)) {
      // 줄어들거나 불일치(이론상 없음)면 delta 없음
      if (!current.startsWith(_lastReply)) _lastReply = current;
      return '';
    }
    final delta = current.substring(_lastReply.length);
    _lastReply = current;
    return delta;
  }

  /// 캐스케이드 재생성 시 상태 초기화.
  void reset() {
    _raw.clear();
    _lastReply = '';
  }

  /// [partialJson]에서 `aiReplyMessage` 문자열 값을 디코딩해 반환.
  /// 닫는 따옴표가 아직 없으면 현재까지의 내용을 반환하며,
  /// 끝에 걸쳐 잘린 이스케이프 시퀀스는 다음 조각이 올 때까지 보류한다.
  static String extract(String partialJson) {
    final match = _keyPattern.firstMatch(partialJson);
    if (match == null) return '';

    final out = StringBuffer();
    var i = match.end;
    while (i < partialJson.length) {
      final ch = partialJson[i];
      if (ch == '"') break; // 값 종료
      if (ch != r'\') {
        out.write(ch);
        i++;
        continue;
      }

      // 이스케이프 시퀀스
      if (i + 1 >= partialJson.length) break; // 잘림 → 보류
      final esc = partialJson[i + 1];
      switch (esc) {
        case 'n':
          out.write('\n');
        case 't':
          out.write('\t');
        case 'r':
          out.write('\r');
        case 'b':
          out.write('\b');
        case 'f':
          out.write('\f');
        case 'u':
          if (i + 6 > partialJson.length) return out.toString(); // 잘림 → 보류
          final code = int.tryParse(partialJson.substring(i + 2, i + 6), radix: 16);
          if (code == null) return out.toString();
          out.writeCharCode(code);
          i += 6;
          continue;
        default:
          // \" \\ \/ 등은 문자 그대로
          out.write(esc);
      }
      i += 2;
    }
    return out.toString();
  }
}
