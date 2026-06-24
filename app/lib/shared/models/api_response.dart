/// 표준 API 응답 래퍼: { success, data, error }.
///
/// 제네릭 봉투(envelope)라 freezed/json_serializable 대신
/// 데이터 변환기를 받는 수동 fromJson을 사용한다.
class ApiResponse<T> {
  const ApiResponse({required this.success, this.data, this.error});

  final bool success;
  final T? data;
  final ApiError? error;

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json) fromJsonT,
  ) {
    final rawData = json['data'];
    return ApiResponse<T>(
      success: json['success'] as bool? ?? false,
      data: rawData == null ? null : fromJsonT(rawData),
      error: json['error'] == null
          ? null
          : ApiError.fromJson(json['error'] as Map<String, dynamic>),
    );
  }
}

/// 표준 응답의 error 객체.
class ApiError {
  const ApiError({required this.code, this.message});

  final String code;
  final String? message;

  factory ApiError.fromJson(Map<String, dynamic> json) => ApiError(
        code: json['code'] as String,
        message: json['message'] as String?,
      );
}
