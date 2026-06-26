import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart';

/// 일기 본문(content) 변환 유틸.
///
/// 본문은 서버에 **Quill Delta JSON 문자열**로 저장된다. 다만 다음 두 경우를
/// 모두 견고하게 처리해야 한다.
/// - 신버전: content가 Delta JSON(`{"ops":[...]}` 또는 `[...]`).
/// - 레거시: content가 순수 텍스트(마이그레이션 전 또는 목록 미리보기 값).
///
/// 또한 글자수 하드 제한(순수 텍스트 500자)·LLM 입력용으로 쓸 **순수 텍스트**를
/// Document에서 추출하는 헬퍼를 제공한다.

/// content 문자열을 Quill [Document]로 변환한다.
///
/// Delta JSON이면 그대로 파싱하고, JSON이 아니면 레거시 plain text로 간주해
/// 한 줄 문서로 만든다. 비어 있으면 빈 문서를 돌려준다.
Document documentFromContent(String? content) {
  final raw = content?.trim() ?? '';
  if (raw.isEmpty) return Document();
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return Document.fromJson(decoded);
    }
    if (decoded is Map && decoded['ops'] is List) {
      return Document.fromJson(decoded['ops'] as List);
    }
  } catch (_) {
    // JSON 파싱 실패 → 레거시 plain text로 처리(아래로 폴백).
  }
  return Document()..insert(0, raw);
}

/// Document를 서버 저장용 Delta JSON 문자열로 직렬화한다.
///
/// flutter_quill의 `Delta.toJson()`은 ops **배열**(`[...]`)을 돌려주지만, 백엔드(이미지
/// 추출·정합)와 목록 SQL(`content::jsonb -> 'ops'`), V4 마이그레이션은 모두 **`{"ops":[...]}`
/// 오브젝트** 형태를 기대한다. 형식을 통일하기 위해 ops를 `{"ops": ...}`로 감싸 저장한다.
String contentJsonFromDocument(Document document) =>
    jsonEncode({'ops': document.toDelta().toJson()});

/// plain text를 Delta JSON 문자열로 래핑한다(시드/테스트용).
String contentJsonFromPlain(String text) =>
    contentJsonFromDocument(Document()..insert(0, text));

/// Document에서 순수 텍스트를 추출한다(글자수 제한·미리보기용).
///
/// - 인라인 이미지 임베드는 object replacement char(`￼`)로 표현되므로 제거.
/// - Quill Document는 항상 끝에 개행 1개가 붙으므로 우측 공백/개행을 정리.
String plainTextOf(Document document) {
  final text = document.toPlainText().replaceAll('￼', '');
  return text.trim();
}
