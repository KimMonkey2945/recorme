/// 커서 페이징 응답: { items, nextCursor, hasNext }.
/// 제네릭이라 데이터 변환기를 받는 수동 fromJson을 사용한다.
class CursorPage<T> {
  const CursorPage({
    required this.items,
    this.nextCursor,
    required this.hasNext,
  });

  final List<T> items;
  final int? nextCursor;
  final bool hasNext;

  factory CursorPage.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json) fromJsonT,
  ) {
    return CursorPage<T>(
      items: (json['items'] as List<dynamic>)
          .map((dynamic e) => fromJsonT(e))
          .toList(),
      nextCursor: (json['nextCursor'] as num?)?.toInt(),
      hasNext: json['hasNext'] as bool? ?? false,
    );
  }
}
