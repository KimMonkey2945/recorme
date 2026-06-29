// ApiDiaryRepository 계약(contract) 테스트.
//
// http_mock_adapter 의존성이 없으므로, Dio의 [httpClientAdapter]를 가짜로 교체해
// 네트워크 없이 표준 응답 봉투(`{success, data, error}`) 언랩/실패 변환 로직을 검증한다.
// - 정상 응답: _unwrap이 Diary/DiarySummary/CursorPage로 매핑하는지
// - 404 응답: getByDate가 null로 매핑하는지
// - 실패 응답(success:false / 비2xx): _toFailure·_unwrap이 Failure(code/message)로 변환하는지
// - 요청 캡처: upsert POST 바디·uploadImages FormData part명("files")이 계약대로인지

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:record/core/error/failure.dart';
import 'package:record/features/diary/data/api_diary_repository.dart';

/// 라우팅 가능한 가짜 HttpClientAdapter.
///
/// [responder]가 [RequestOptions]를 보고 응답 본문을 결정한다.
/// 마지막 요청 옵션을 [lastOptions]에 보관해 요청 캡처 검증에 사용한다.
class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this.responder);

  /// 요청을 받아 (statusCode, jsonBody)를 돌려주는 함수.
  final (int, Map<String, dynamic>) Function(RequestOptions options) responder;

  /// 마지막으로 들어온 요청(요청 바디 캡처용).
  RequestOptions? lastOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    final (status, body) = responder(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 가짜 어댑터가 장착된 Dio를 만든다. baseUrl은 실제 호출이 없으므로 임의값.
Dio _dioWith(_MockAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api/v1'))
    // 격리 없이 동기 디코딩 — 테스트 결정성 확보(isolate 미사용).
    ..transformer = SyncTransformer()
    ..httpClientAdapter = adapter;
  return dio;
}

/// 성공 봉투 헬퍼.
Map<String, dynamic> _ok(Object? data) => {'success': true, 'data': data};

/// 실패 봉투 헬퍼.
Map<String, dynamic> _fail(String code, String message) => {
      'success': false,
      'data': null,
      'error': {'code': code, 'message': message},
    };

void main() {
  group('ApiDiaryRepository 계약', () {
    test('getByDate: 404 응답이면 null로 매핑', () async {
      final adapter = _MockAdapter(
        (_) => (404, _fail('DIARY_NOT_FOUND', '해당 날짜 일기가 없어요.')),
      );
      final repo = ApiDiaryRepository(_dioWith(adapter));

      final result = await repo.getByDate(DateTime(2026, 6, 24));
      expect(result, isNull);
      // 경로가 yyyy-MM-dd로 구성되는지 확인.
      expect(adapter.lastOptions!.path, '/diaries/by-date/2026-06-24');
    });

    test('getById: 성공 봉투를 Diary로 언랩(content Delta·contentText)', () async {
      final adapter = _MockAdapter(
        (_) => (
          200,
          _ok({
            'id': 7,
            'content': '{"ops":[{"insert":"상세 본문\\n"}]}',
            'contentText': '상세 본문',
            'writtenDate': '2026-06-24',
            'visibility': 'PRIVATE',
            'analysisStatus': 'DONE',
          }),
        ),
      );
      final repo = ApiDiaryRepository(_dioWith(adapter));

      final diary = await repo.getById(7);
      expect(diary.id, 7);
      expect(diary.content, '{"ops":[{"insert":"상세 본문\\n"}]}');
      expect(diary.contentText, '상세 본문');
      expect(diary.analysisStatus, 'DONE');
      expect(adapter.lastOptions!.path, '/diaries/7');
    });

    test('getMonthlySummary: 성공 봉투를 DiarySummary로 언랩', () async {
      final adapter = _MockAdapter(
        (_) => (
          200,
          _ok({
            'yearMonth': '2026-06',
            'days': [
              {
                'date': '2026-06-01',
                'analysisStatus': 'DONE',
                'primaryEmotion': 'JOY',
                'moodEmoji': '😊',
              },
              {
                'date': '2026-06-10',
                'analysisStatus': 'DRAFT',
                'primaryEmotion': null,
                'moodEmoji': null,
              },
            ],
          }),
        ),
      );
      final repo = ApiDiaryRepository(_dioWith(adapter));

      final summary = await repo.getMonthlySummary('2026-06');
      expect(summary.yearMonth, '2026-06');
      // days 파싱: 2개 항목, 날짜·상태 검증
      expect(summary.days.length, 2);
      expect(summary.days[0].date, '2026-06-01');
      expect(summary.days[0].isDone, isTrue);
      expect(summary.days[0].primaryEmotion, 'JOY');
      expect(summary.days[1].date, '2026-06-10');
      expect(summary.days[1].isDraft, isTrue);
      expect(summary.days[1].moodEmoji, isNull);
      // 쿼리 파라미터로 yearMonth가 실리는지 확인.
      expect(adapter.lastOptions!.queryParameters['yearMonth'], '2026-06');
    });

    test('getList: 성공 봉투를 CursorPage<Diary>로 언랩', () async {
      final adapter = _MockAdapter(
        (_) => (
          200,
          _ok({
            'items': [
              {
                'id': 5,
                'content': '다섯',
                'writtenDate': '2026-06-25',
                'analysisStatus': 'DONE',
              },
              {
                'id': 3,
                'content': '셋',
                'writtenDate': '2026-06-23',
                'analysisStatus': 'PENDING',
              },
            ],
            'nextCursor': 3,
            'hasNext': true,
          }),
        ),
      );
      final repo = ApiDiaryRepository(_dioWith(adapter));

      final page = await repo.getList(size: 2);
      expect(page.items.length, 2);
      expect(page.items.first.id, 5);
      // 목록 응답엔 visibility가 없어도 tolerant 기본값 처리.
      expect(page.items.first.visibility, 'PRIVATE');
      expect(page.nextCursor, 3);
      expect(page.hasNext, true);
      expect(adapter.lastOptions!.path, '/diaries/me');
      expect(adapter.lastOptions!.queryParameters['size'], 2);
    });

    test('실패 봉투(200 + success:false)는 Failure(code/message)로 변환', () async {
      final adapter = _MockAdapter(
        (_) => (200, _fail('DIARY_NOT_FOUND', '일기를 찾을 수 없어요.')),
      );
      final repo = ApiDiaryRepository(_dioWith(adapter));

      await expectLater(
        repo.getById(99),
        throwsA(
          isA<Failure>()
              .having((f) => f.code, 'code', 'DIARY_NOT_FOUND')
              .having((f) => f.message, 'message', '일기를 찾을 수 없어요.'),
        ),
      );
    });

    test('비2xx 응답은 error 바디를 추출해 Failure로 변환', () async {
      final adapter = _MockAdapter(
        (_) => (500, _fail('INTERNAL_ERROR', '서버 오류가 발생했어요.')),
      );
      final repo = ApiDiaryRepository(_dioWith(adapter));

      await expectLater(
        repo.getById(1),
        throwsA(
          isA<Failure>()
              .having((f) => f.code, 'code', 'INTERNAL_ERROR')
              .having((f) => f.message, 'message', '서버 오류가 발생했어요.'),
        ),
      );
    });

    test('upsert: POST 바디에 content·contentText·writtenDate(yyyy-MM-dd)가 실린다',
        () async {
      final adapter = _MockAdapter(
        (_) => (
          201,
          _ok({
            'id': 1,
            'content': '{"ops":[{"insert":"오늘의 기록\\n"}]}',
            'contentText': '오늘의 기록',
            'writtenDate': '2026-06-24',
            'visibility': 'PRIVATE',
            'analysisStatus': 'PENDING',
          }),
        ),
      );
      final repo = ApiDiaryRepository(_dioWith(adapter));

      final saved = await repo.upsert(
        date: DateTime(2026, 6, 24),
        content: '{"ops":[{"insert":"오늘의 기록\\n"}]}',
        contentText: '오늘의 기록',
      );
      expect(saved.id, 1);
      expect(saved.analysisStatus, 'PENDING');

      // 요청 캡처: 메서드·경로·바디 검증.
      final opts = adapter.lastOptions!;
      expect(opts.method, 'POST');
      expect(opts.path, '/diaries');
      final body = opts.data as Map<String, dynamic>;
      expect(body['content'], '{"ops":[{"insert":"오늘의 기록\\n"}]}');
      expect(body['contentText'], '오늘의 기록');
      expect(body['writtenDate'], '2026-06-24');
    });

    test('uploadImage: FormData part명 "file"로 1장 전송 + url 언랩', () async {
      final adapter = _MockAdapter(
        (_) => (200, _ok({'url': '/files/diaries/2026/06/x.png'})),
      );
      final repo = ApiDiaryRepository(_dioWith(adapter));

      final url = await repo.uploadImage(
        Uint8List.fromList(const [1, 2, 3]),
        'a.jpg',
      );
      expect(url, '/files/diaries/2026/06/x.png');

      final opts = adapter.lastOptions!;
      expect(opts.method, 'POST');
      expect(opts.path, '/diaries/images');
      final form = opts.data as FormData;
      expect(form.files.length, 1);
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.filename, 'a.jpg');
    });
  });
}
