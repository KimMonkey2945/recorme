/// 도메인 계층으로 전달되는 실패 표현.
/// 표준 응답의 error.code/message 또는 네트워크/파싱 오류를 매핑한다.
class Failure implements Exception {
  const Failure(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'Failure($code: $message)';
}
