# Task 031 — 에셋 제작 + Rive 비트맵 리깅 렌더러 교체

- **Phase**: 7 (캐릭터 중심 전환)
- **구현 기능**: F026 (캐릭터 렌더 최종 품질)
- **상태**: 미착수 (사용자가 **Rive로 캐릭터를 제작해 넣을 예정**)
- **선행**: Task 029(대체 렌더러·`character_stage` 스위치 — **완료**), Task 030(옷장·상점)

> ⚠️ **에셋 의존 작업이므로 최후 배치.** 선행 Task는 전부 **비-Rive 렌더러**로 **완결돼 있어야** 한다.
> 이 Task가 늦어져도 제품 기능은 전부 동작한다(크리티컬 패스에서 제거된 상태).

## 개요

확보된 **3D 렌더풍 정면 PNG 2장**을 파츠로 잘라 **Rive에 비트맵 그대로 넣고 본을 심는다**(벡터 재작화 없음).
의상·소품은 `.riv`에 **굽지 않고** Data Binding `image` 프로퍼티에 **런타임 주입** → **아이템 추가에 앱 재배포 불필요**.

### ★★ 가장 중요한 전제 — Rive 런타임은 **PNG를 애니메이션하지 못한다**

Rive Flutter 공식 문서:

> "The Flutter runtime does not provide animation capabilities for plain PNG images.
> It exclusively works with Rive's native format."

즉 **`rive` 패키지를 pubspec에 넣는 것만으로는 아무 일도 일어나지 않는다.**
런타임은 **`.riv` 아트보드를 재생하는 플레이어**일 뿐이고, 움직임은 전부 **에디터에서 비트맵을 리깅해 `.riv`로 구운 결과물** 안에 들어 있다.
→ **이 Task의 실질은 코드가 아니라 에셋 제작(①~⑥)이며, `.riv`가 선행되지 않으면 런타임 연결은 착수 자체가 무의미하다.**

그래서 **`rive` 패키지를 아직 pubspec에 넣지 않았다.** 재생할 `.riv`가 없는 상태에서 **네이티브 dev 릴리스**(`rive: ^0.14.0-dev.6`, `rive_native` FFI 의존)를 미리 얹으면 **얻는 것 없이 빌드 리스크만 커진다.** `.riv` 확보 시점에 추가한다.

### 현재 대체 렌더러는 `PlaceholderCharacterView`가 **아니다**

Task 029에서 PNG Stack 합성(`PlaceholderCharacterView`) 대신 **`IdleCharacterView`(메시 워프)** 를 구현했다.
`Canvas.drawVertices` + `ImageShader`로 PNG를 **12×16 격자 메시**로 쪼개 정점마다 다르게 변형한다 —
**발 고정 스웨이**(`v^1.6` 가중) · **숨쉬기 스쿼시&스트레치**(부피 보존 근사) · **머리 두리번** · **12초 주기의 정수배 하모닉 합성**(루프 경계 무이음).
이미지를 통째로 `Transform`하면 **판자가 흔들리는 모양**이 되는데, Rive가 자연스러운 이유가 런타임이 아니라 **아트보드가 메시로 리깅돼 있기 때문**이라서 같은 원리를 Flutter에서 직접 구현한 것이다.
→ **Rive로 교체할 때 대체되는 대상은 `IdleCharacterView`다.**

### 에셋 전제 (미해결)

현재 `app/assets/characters/{monkey,red_panda}.png`는 **배경이 불투명한 크림색**이다.
파츠 분리·슬롯 합성 모두 **투명 PNG가 전제**이며, **사용자가 투명 배경 PNG를 준비하기로 했다.**

### 왜 Rive 비트맵 리깅인가
- **실시간 3D 탈락**: `flutter_scene`은 early preview + master 채널 필수. `model_viewer_plus`/`flutter_3d_controller`는
  WebView에 `<model-viewer>`를 얹는 방식 — 홈에 상시 띄우기엔 메모리·배터리·첫 프레임 지연이 모두 나쁘다.
  **캐릭터를 돌려볼 필요가 없으므로 3D 엔진을 넣을 이유가 없다. 3D 룩은 이미 이미지 안에 있다.**
- **Spine 탈락**: 유일하게 유료($99~)인데 파츠 컷아웃 노동이 가장 크고, 서버 아이템 추가가 Rive보다 어렵다.
- **Rive 채택**: 비트맵 그대로 본에 바인딩 → 1인 개발로 감당 가능. 캐릭터가 2종뿐이라 리깅 부담이 작다. MIT, 무료.

### ⚠️ 핵심 제약 — 옷은 캐릭터별로 따로 그려야 한다
원숭이와 레서판다는 체형이 다르다(레서판다가 통통하고 팔이 짧음). **셔츠 1종 = PNG 2장.**
**캐릭터가 늘면 옷 에셋이 곱셈으로 늘어난다** → 캐릭터 추가는 아이템 수가 적을 때 신중히.

### 진행 원칙
**먼저 캐릭터 1종 + 아이템 2개로 전 구간(DB → API → 상점 → 착용 → 렌더)을 관통시킨 뒤** 나머지를 채운다.

## 관련 파일

- `app/assets/characters/{monkey,red_panda}.png` — **투명 배경 PNG로 교체 필요**(현재 크림색 불투명)
- `app/assets/rive/characters.riv` — **신규**(아트보드 `MONKEY`·`RED_PANDA`) — **이것이 없으면 나머지는 전부 무의미**
- `app/lib/features/character/presentation/widgets/rive_character_view.dart` — **신규**
- `app/lib/features/character/presentation/widgets/character_stage.dart` — ✅ 스위치 완성(Task 029).
  **드롭인 지점**: `USE_RIVE` 분기에 주석으로 자리가 준비돼 있다(`riveEnabled = useRive && !kIsWeb`)
- `app/lib/features/character/presentation/widgets/idle_character_view.dart` — **Rive 교체 대상**(현 대체 렌더러)
- `app/lib/shared/character/rive_image_cache.dart` — **신규**(url → bytes **메모리 LRU + 디스크 캐시**)
- `app/pubspec.yaml` — `rive` 의존성 + `assets/rive/` 등록 — **아직 미추가**(`.riv` 확보 시점에)
- 서버 `/files/items/**` — 아이템 PNG 업로드 → `character_items.image_url` 등록
- `docs/mobile.md` — Rive 도입·에셋 제작 워크플로우 절(별도 작업)

## 구현 항목 (에셋 워크플로우)

- [ ] **① 맨몸 베이스 생성** — 현재 PNG는 흰 티 + 검은 반바지 착용 → AI/생성 채우기로 **옷 없는 버전** 제작.
      지금의 흰 티·검은 반바지는 **첫 의상 아이템**(`OUTFIT/BASIC_TEE`·`OUTFIT/BASIC_SHORTS`)으로 등록
      → 몸에 밀착하는 셀프·반팔·수영복이 나중에 가능해진다
- [ ] **② 파츠 분리** — 배경 제거 후 레이어 분해. 가려진 부분(팔 뒤 몸통 등)은 **인페인팅으로 복원**
      ```
      head.png / ears.png / eyes.png (+ 깜빡임용 감은 눈 1장)
      body.png / arm_L.png / arm_R.png / leg_L.png / leg_R.png / tail.png
      ```
- [ ] **③ Rive 아트보드 조립** — 캐릭터당 1개, 이름 = DB `characters.code`(`MONKEY`·`RED_PANDA`).
      1:1 캔버스(1000×1000), 하단 정렬. 파츠를 **비트맵 그대로** 배치하고 본(spine/head/arm/tail)에 바인딩
- [ ] **④ State Machine `SM_Character`**(전 아트보드 동일):
      `Idle`(루프 — 숨쉬기(spine 미세 스케일) + 눈 깜빡임(랜덤) + **주기적으로 고개 돌려 두리번거림**) /
      `React`(1회 → Idle 복귀) / `Celebrate`(1회) / `Wave`(선택 시)
- [ ] **⑤ ViewModel `CharacterVM`**(default instance export). **감정 프로퍼티 없음**

| 프로퍼티 | 타입 | 용도 |
|---|---|---|
| `hat` `outfit` `glasses` `prop` `background` | Image | 슬롯 런타임 주입(null=미착용) |
| `roomProp0`~`roomProp5` | Image | 방 소품 진열 |
| `speech` `nickname` | String | 말풍선·이름 |
| `level` `expRatio`(0~1) | Number | 뱃지·성장 게이지 |
| `react` `celebrate` `wave` | Trigger | 1회 재생 |

- [ ] **⑥ 슬롯 앵커** — 각 Image 노드를 해당 본(머리/몸통/손)에 부착해 애니메이션 시 함께 움직이게.
      아이템 PNG는 **그 슬롯 프레임을 꽉 채우도록 미리 정렬**해 export(512×512 투명, ≤80KB).
      **캐릭터마다 프레임 위치·크기가 다르므로 아이템도 캐릭터별로 export**한다
- [ ] **⑦ 아이템은 `.riv`에 굽지 않는다** — 서버 `/files/items/` 업로드 → `character_items.image_url` 등록 →
      앱이 다운로드·캐시 후 주입 → **아이템 추가에 앱 배포 불필요**

## 구현 항목 (런타임 연결)

- [ ] `pubspec.yaml`에 `rive: ^0.14.0-dev.6` 추가 + `main()`에서 `await RiveNative.init()`(네이티브 FFI 초기화)
- [ ] `rive_character_view.dart`:
  ```dart
  // main(): WidgetsFlutterBinding.ensureInitialized(); await RiveNative.init();
  final file = await rive.File.asset('assets/rive/characters.riv', riveFactory: rive.Factory.rive);
  _controller = rive.RiveWidgetController(file,
      artboardSelector: rive.ArtboardSelector.byName(spec.riveArtboard),   // 'MONKEY' | 'RED_PANDA'
      stateMachineSelector: rive.StateMachineSelector.byName('SM_Character'));
  _vmi = _controller.dataBind(rive.DataBind.auto());
  // 렌더: return rive.RiveWidget(controller: _controller, fit: rive.Fit.contain);

  final bytes = await ref.read(riveImageCacheProvider).load(variant.imageUrl);
  _vmi.image('outfit')?.value = await rive.Factory.rive.decodeImage(bytes);
  _vmi.string('speech')?.value = reaction.line;
  _vmi.number('expRatio')?.value = exp / expToNext;
  _vmi.trigger('react')?.fire();
  ```
- [ ] `rive_image_cache.dart` — 메모리 LRU + 디스크 캐시(같은 아이템 재다운로드 방지)
- [x] `character_stage.dart` — `USE_RIVE=true`일 때 Rive 경로 선택. **`kIsWeb`이면 무조건 비-Rive**(`rive_native` wasm 이슈 회피)
      → **스위치는 Task 029에서 완성**. Rive 분기에 위젯을 드롭인하기만 하면 된다
- [ ] 컨트롤러 `dispose` 정확히 처리(홈 재진입 반복 시 누수 금지)

## 성능 예산

- [ ] 아트보드당 본 **≤40**
- [ ] `.riv` 파일 **≤1.5MB**
- [ ] 이미지는 **referenced**(embed 금지)
- [ ] 아이템 PNG 512×512 투명 **≤80KB**

## 수락 기준

- [ ] 2종 아트보드(`MONKEY`·`RED_PANDA`)가 실기기에서 정상 로드·재생
- [ ] 착용/해제/교체가 슬롯 이미지 스왑으로 **즉시 반영**
- [ ] 캐릭터 전환 시 **variant 재주입**(옷장 유지 — Task 027 설계와 정합)
- [ ] 홈 재진입 반복 시 **메모리 누수 없음**
- [ ] `kIsWeb`에서 플레이스홀더 폴백
- [ ] **Task 029/030의 위젯 테스트가 그대로 통과**(플레이스홀더 경로 무손상)

## 구현 단계

1. [ ] 맨몸 베이스 생성(2종) + 기존 흰 티·검은 반바지를 첫 의상 아이템으로 분리
2. [ ] 파츠 분리 + 인페인팅 복원(2종)
3. [ ] Rive 아트보드 조립 + 본 바인딩(**먼저 1종만**)
4. [ ] `SM_Character` State Machine + `CharacterVM` ViewModel 정의
5. [ ] **캐릭터 1종 + 아이템 2개로 전 구간 관통**(DB → API → 상점 → 착용 → 렌더) 확인
6. [ ] 나머지 캐릭터·아이템 variant export 및 서버 업로드
7. [ ] `rive_character_view` + `rive_image_cache` 구현, `character_stage` Rive 경로 활성화
8. [ ] 실기기 수동 테스트 → **전 항목 통과 확인 후에만 완료 처리**

## 테스트 체크리스트 (실기기 수동 — Z Flip3 + iOS)

> ⚠️ Rive는 **네이티브 FFI 의존**이라 위젯 테스트로 커버할 수 없다.
> **위젯 테스트는 플레이스홀더 경로를 유지**하고(Task 029/030 무손상), Rive는 실기기 수동 검증으로 대체한다.

### 렌더/애니메이션
- [ ] 2종 아트보드(`MONKEY`·`RED_PANDA`) 정상 로드 + 첫 프레임 지연 체감 없음
- [ ] **Idle 두리번거림 + 숨쉬기 + 눈 깜빡임** 자연 재생(루프)
- [ ] `react` / `celebrate` 트리거 **1회 재생 후 Idle 복귀**
- [ ] `speech`(말풍선) · `level` · `expRatio`(성장 게이지) 데이터 바인딩 반영

### 아이템 슬롯 (핵심)
- [ ] 착용 → 슬롯 이미지 **즉시 스왑** / 해제 → 슬롯 비움 / 교체 → 새 이미지로 스왑
- [ ] **캐릭터 전환 시 variant 재주입** — 같은 group이 새 캐릭터 체형에 맞는 PNG로 바뀜
- [ ] `ROOM_PROP` 0~5 다중 진열 렌더
- [ ] `rive_image_cache` — 같은 아이템 재착용 시 **재다운로드 없음**(캐시 히트)
- [ ] 아이템 이미지 로드 실패 시 해당 슬롯만 생략(캐릭터는 정상)

### 성능/안정성
- [ ] **홈 재진입 50회 → dispose 누수 없음**(메모리 프로파일)
- [ ] `.riv` ≤1.5MB / 본 ≤40 / 아이템 PNG ≤80KB 예산 준수
- [ ] **APK 증가분 기록**(Rive 도입 전후 비교)
- [ ] 저사양/백그라운드 복귀 시 애니메이션 정상 재개
- [ ] **웹(`kIsWeb`)에서 플레이스홀더 폴백**(`rive_native` wasm 이슈 회피)

### 회귀
- [ ] `USE_RIVE=false`에서 기존 플레이스홀더 경로 정상(스위치 양방향 동작)
- [ ] Task 029/030 `flutter test` **전체 통과 유지**

## 변경 사항 요약

- **미착수.** 아래는 착수 전 확정된 전제다(구현 결과 아님).

### 착수 전 확정 전제

1. **런타임은 `.riv` 없이는 아무것도 못 한다.** Rive Flutter 런타임은 **일반 PNG를 애니메이션하는 기능을 제공하지 않으며, Rive 네이티브 포맷만 다룬다**(공식 문서). → **에디터에서 비트맵 리깅한 `.riv`가 이 Task의 유일한 크리티컬 인풋**이다.
2. **`rive` 패키지는 아직 pubspec에 없다.** 재생할 `.riv`가 없는 상태에서 네이티브 FFI dev 릴리스를 얹으면 **효과 0 · 빌드 리스크만 증가**. `.riv` 확보와 **동시에** 추가한다.
3. **대체 렌더러는 `IdleCharacterView`(메시 워프)** — 원안의 `PlaceholderCharacterView`(PNG Stack)가 아니다. Rive가 교체할 대상은 이쪽이다.
4. **드롭인 지점은 준비 완료** — `character_stage.dart`의 `USE_RIVE` 분기(주석). 스위치·웹 폴백은 Task 029에서 이미 동작한다.
5. **에셋 블로커**: 현재 캐릭터 PNG 2장은 **배경이 불투명한 크림색**. 파츠 분리·슬롯 합성 모두 투명 PNG가 전제이며, **사용자가 투명 PNG를 준비하기로 했다.**
