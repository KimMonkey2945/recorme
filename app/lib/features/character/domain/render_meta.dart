/// 장착 아이템의 2D 렌더 메타(비-Rive 폴백 렌더러가 사용).
///
/// 백엔드 `renderMeta` JSON(`{anchorX, anchorY, scale, z}`)과 1:1 대응한다.
/// - [anchorX]·[anchorY]: 캐릭터 스테이지(0~1 정규화 좌표) 기준 앵커 위치.
/// - [scale]: 스테이지 크기 대비 아이템 배율.
/// - [z]: 겹침 순서(작을수록 뒤).
///
/// 아이템 오버레이 렌더는 Task 030/031 범위이며, 여기서는 계약만 파싱해 둔다.
class RenderMeta {
  const RenderMeta({
    required this.anchorX,
    required this.anchorY,
    required this.scale,
    required this.z,
  });

  final double anchorX;
  final double anchorY;
  final double scale;
  final int z;
}
