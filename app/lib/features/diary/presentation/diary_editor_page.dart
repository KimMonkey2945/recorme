import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../data/dto/diary_dto.dart';
import '../domain/diary_content.dart';
import 'providers/diary_providers.dart';
import 'widgets/diary_editor_view.dart';

/// 기록 작성/수정 화면.
///
/// 라우트 쿼리 [date](yyyy-MM-dd)로 대상 날짜를 받는다. 해당 날짜에 기록이 있으면
/// 수정 모드(기존 Delta 프리필), 없으면 신규 작성. 저장은 upsert(하루 1기록).
///
/// 본문은 [QuillController]로 리치 텍스트(서식·인라인 이미지)를 다룬다. 사진은
/// 작성 중 [uploadImage]로 즉시 업로드해 반환된 경로를 본문 Delta에 임베드하고,
/// 저장 시 서버가 Delta를 파싱해 실제 사용 이미지를 확정한다(별도 첨부 단계 없음).
class DiaryEditorPage extends ConsumerStatefulWidget {
  const DiaryEditorPage({super.key, this.date});

  /// YYYY-MM-DD. null이면 오늘 날짜로 신규 작성.
  final String? date;

  @override
  ConsumerState<DiaryEditorPage> createState() => _DiaryEditorPageState();
}

class _DiaryEditorPageState extends ConsumerState<DiaryEditorPage> {
  /// 본문에 삽입 가능한 최대 사진 수.
  static const int _maxPhotos = 5;

  /// 본문 최대 글자 수(순수 텍스트 기준 하드 제한).
  static const int _maxLength = 500;

  late final DateTime _date;
  late final QuillController _controller;

  bool _saving = false;
  bool _picking = false;

  /// 기존 기록 본문을 1회만 프리필했는지 여부(rebuild 시 사용자 편집 보존).
  bool _prefilled = false;

  /// 확정 기록 진입 시 상세로 리다이렉트를 1회만 트리거하기 위한 가드.
  bool _redirectingToDetail = false;

  /// 현재 순수 텍스트 길이(카운터·저장 가능 판단용).
  int _plainLength = 0;

  /// 글자수 초과 시 되돌릴 마지막 유효 상태.
  String _lastValidJson = '';
  TextSelection _lastValidSelection = const TextSelection.collapsed(offset: 0);

  /// 제한 초과 되돌리기 중 재진입(리스너 재호출) 방지 플래그.
  bool _enforcing = false;

  @override
  void initState() {
    super.initState();
    final parsed = widget.date != null ? DateTime.tryParse(widget.date!) : null;
    final base = parsed ?? DateTime.now();
    // 미래 날짜로 직접 진입(라우트 조작 등)하면 오늘로 클램프(방어).
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final baseDay = DateTime(base.year, base.month, base.day);
    _date = baseDay.isAfter(today) ? today : baseDay;

    _controller = QuillController.basic();
    _lastValidJson = contentJsonFromDocument(_controller.document);
    _controller.addListener(_onDocumentChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onDocumentChanged)
      ..dispose();
    super.dispose();
  }

  String get _dateText => '${_date.year}년 ${_date.month}월 ${_date.day}일';

  bool get _canSave => _plainLength > 0 && !_saving;

  /// 기존 기록이 처음 도착하면 Delta를 1회 프리필한다.
  void _ensurePrefilled(Diary? diary) {
    if (_prefilled) return;
    _prefilled = true;
    if (diary != null) {
      _controller.document = documentFromContent(diary.content);
    }
    _lastValidJson = contentJsonFromDocument(_controller.document);
    _lastValidSelection = _controller.selection;
    _plainLength = plainTextOf(_controller.document).length;
  }

  /// 본문 변경 감지 → 글자수 갱신 + 순수 텍스트 500자 하드 제한.
  void _onDocumentChanged() {
    if (_enforcing) return;
    final length = plainTextOf(_controller.document).length;

    if (length > _maxLength) {
      // 초과분이 생긴 변경 → 마지막 유효 상태로 되돌린다.
      _enforcing = true;
      _controller.document = documentFromContent(_lastValidJson);
      final docLen = _controller.document.length;
      final offset = _lastValidSelection.baseOffset.clamp(0, docLen - 1);
      _controller.updateSelection(
        TextSelection.collapsed(offset: offset),
        ChangeSource.local,
      );
      _enforcing = false;
      if (mounted) {
        showAppSnackBar(context, '본문은 최대 $_maxLength자까지 작성할 수 있어요');
        setState(() => _plainLength = plainTextOf(_controller.document).length);
      }
      return;
    }

    _lastValidJson = contentJsonFromDocument(_controller.document);
    _lastValidSelection = _controller.selection;
    if (length != _plainLength && mounted) {
      setState(() => _plainLength = length);
    }
  }

  /// 본문에 박힌 이미지(임베드) 개수.
  int _imageCount() {
    var count = 0;
    for (final op in _controller.document.toDelta().toList()) {
      final data = op.data;
      if (data is Map && data.containsKey('image')) count++;
    }
    return count;
  }

  /// 사진 삽입: 갤러리 1장 선택 → 업로드 → 커서 위치에 image 임베드 삽입.
  Future<void> _onPickImage() async {
    if (_picking || _saving) return;
    if (_imageCount() >= _maxPhotos) {
      showAppSnackBar(context, '사진은 최대 $_maxPhotos장까지 넣을 수 있어요');
      return;
    }
    _picking = true;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final filename = picked.name.isNotEmpty ? picked.name : 'image.jpg';
      final url = await ref.read(diaryRepositoryProvider).uploadImage(bytes, filename);
      if (!mounted) return;

      // 현재 커서(없으면 문서 끝)에 이미지 임베드 삽입.
      final selection = _controller.selection;
      final index = selection.isValid
          ? selection.baseOffset
          : _controller.document.length - 1;
      final length =
          selection.isValid ? selection.extentOffset - selection.baseOffset : 0;
      _controller.replaceText(
        index,
        length,
        BlockEmbed.image(url),
        TextSelection.collapsed(offset: index + 1),
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, '이미지 업로드에 실패했어요', isError: true);
    } finally {
      _picking = false;
    }
  }

  /// provider 캐시 전체를 무효화한다(저장·확정 후 공통 처리).
  void _invalidateAll() {
    ref.invalidate(monthlySummaryProvider);
    ref.invalidate(monthDiariesProvider);
    ref.invalidate(diaryByDateProvider);
    ref.invalidate(diaryByIdProvider);
  }

  /// 409(DIARY_ALREADY_CONFIRMED) 포함 저장 오류를 스낵바로 안내한다.
  void _handleSaveError(Object e) {
    if (!mounted) return;
    if (e is Failure && e.code == 'DIARY_ALREADY_CONFIRMED') {
      showAppSnackBar(context, '이미 기억한 일기는 수정할 수 없어요', isError: true);
    } else {
      showAppSnackBar(context, '저장에 실패했어요', isError: true);
    }
    setState(() => _saving = false);
  }

  /// '등록' 탭 — confirm:false로 임시 저장(DRAFT). 저장 후 이전 화면으로 복귀.
  Future<void> _onRegister() async {
    final plain = plainTextOf(_controller.document);
    if (plain.isEmpty) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(diaryRepositoryProvider);
      final content = contentJsonFromDocument(_controller.document);
      // 임시 저장: confirm 생략(기본값 false) → analysisStatus: DRAFT
      await repo.upsert(date: _date, content: content, contentText: plain);

      // 캘린더 dot·월 목록·날짜/단건 캐시 갱신.
      _invalidateAll();
      if (!mounted) return;
      showAppSnackBar(context, '저장했어요');
      context.pop();
    } catch (e) {
      _handleSaveError(e);
    }
  }

  /// '오늘을 기억하기' 탭 — 확인 다이얼로그 후 confirm:true로 확정.
  /// 확정 후에는 상세 화면으로 이동해 AI 분석 폴링을 노출한다.
  Future<void> _onRemember() async {
    final plain = plainTextOf(_controller.document);
    if (plain.isEmpty) return;

    // 수정 불가 안내 포함 확인 다이얼로그.
    final confirmed = await showConfirmDialog(
      context,
      title: '오늘을 기억하기',
      message: '기억하면 더 이상 수정할 수 없어요. 진행할까요?',
      confirmLabel: '기억하기',
    );
    if (!confirmed || !mounted) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(diaryRepositoryProvider);
      final content = contentJsonFromDocument(_controller.document);
      // 확정: confirm=true → analysisStatus: PENDING(AI 분석 대기)
      final diary = await repo.upsert(
        date: _date,
        content: content,
        contentText: plain,
        confirm: true,
      );

      // 캘린더 dot·월 목록·날짜/단건 캐시 갱신.
      _invalidateAll();
      if (!mounted) return;
      // 상세 화면으로 이동(분석 폴링 카드 표시).
      // TODO: 로직 연결 지점 — pushReplacement로 에디터 스택 제거 후 상세 진입.
      context.pushReplacement('/diary/${diary.id}');
    } catch (e) {
      _handleSaveError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = ref.watch(diaryByDateProvider(_date));

    return Container(
      decoration: const BoxDecoration(gradient: AppColors.bgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
        ),
        body: SafeArea(
          child: existing.when(
            loading: () => const LoadingView(),
            // 조회 실패(404 아님 — getByDate가 404는 null로 처리) 시 빈 에디터로 진입하면
            // 저장 시 upsert가 기존 기록을 덮어쓸 수 있다. 편집을 막고 재시도를 제공한다.
            error: (_, _) => ErrorView(
              message: '일기를 불러오지 못했어요',
              onRetry: () => ref.invalidate(diaryByDateProvider(_date)),
            ),
            data: (diary) {
              // 확정 기록(isDraft=false)은 수정 불가 — /editor 직접 URL 접근 방어.
              // 편집기 대신 안내 후 상세 화면으로 대체 이동한다(저장 시점 에러 회피).
              if (diary != null && !diary.isDraft) {
                if (!_redirectingToDetail) {
                  _redirectingToDetail = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    showAppSnackBar(context, '이미 확정된 일기는 수정할 수 없어요');
                    context.pushReplacement('/diary/${diary.id}');
                  });
                }
                return const LoadingView();
              }
              _ensurePrefilled(diary);
              return _editorView();
            },
          ),
        ),
      ),
    );
  }

  Widget _editorView() => DiaryEditorView(
        dateText: _dateText,
        controller: _controller,
        plainLength: _plainLength,
        maxLength: _maxLength,
        saving: _saving,
        canSave: _canSave,
        onRegister: _onRegister,
        onRemember: _onRemember,
        onCancel: () => context.pop(),
        onPickImage: _onPickImage,
      );
}
