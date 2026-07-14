-- =====================================================================
-- V15__add_character_catalog.sql — 캐릭터 도메인 ① 카탈로그(마스터)
-- 원본: tasks/026-db-character-schema.md
-- 범위: characters(캐릭터 마스터) + item_groups(소유·착용 단위) +
--       character_items(렌더 단위 variant) + character_lines(맥락 대사).
--
-- ★ 핵심 설계 — group(소유·착용) ↔ variant(렌더) 2단 구조
--   원숭이와 레서판다는 체형이 달라 같은 "빨간 후드티"라도 PNG 를 따로 그려야 한다.
--   그래서 사용자는 item_groups.code 를 소유·착용하고(user_item_groups / user_equipment),
--   렌더 시점에만 (group_code + 선택 캐릭터) → character_items 로 variant 를 해석한다.
--   → 캐릭터를 교체해도 옷장(소유·착용)이 그대로 따라온다.
--
-- 전부 마스터 테이블이라 변경 빈도가 낮다(027 CatalogCache 메모리 캐시 대상).
-- 시드는 ON CONFLICT DO NOTHING 으로 멱등(emotion_types 관례, V7).
-- =====================================================================

-- ========== 캐릭터 마스터 ==========
-- 온보딩에서 무료 선택하는 캐릭터. 코드가 PK(FK 대상)이며 라벨·에셋 경로는 여기서만 관리한다.
CREATE TABLE characters (
    code          VARCHAR(30) PRIMARY KEY,                  -- MONKEY / RED_PANDA (FK 대상)
    name_ko       VARCHAR(30) NOT NULL,                     -- 한국어 표시 이름
    tagline       VARCHAR(100) NOT NULL,                    -- 온보딩 소개 문구(성격 한 줄)
    rive_artboard VARCHAR(50) NOT NULL,                     -- Rive 아트보드명(앱 렌더러가 참조)
    thumbnail_url TEXT NOT NULL,                            -- 앱 로컬 에셋 경로(assets/characters/*.png)
    sort_order    INT NOT NULL DEFAULT 0,                   -- 선택 화면 정렬(작을수록 먼저)
    active        BOOLEAN NOT NULL DEFAULT true,            -- false=신규 선택 불가(기존 선택자는 유지)
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 캐릭터 2종 시드. 성격 대비(느긋함 vs 부지런함)가 대사(character_lines)까지 이어진다.
INSERT INTO characters (code, name_ko, tagline, rive_artboard, thumbnail_url, sort_order, active) VALUES
    ('MONKEY',    '원숭이',   '뭐든 천천히, 오늘도 느긋하게. 여유가 특기인 친구예요.',
     'monkey',    'assets/characters/monkey.png',    0, true),
    ('RED_PANDA', '레서판다', '부지런히 곁을 지켜요. 정 많고 애착이 강한 친구예요.',
     'red_panda', 'assets/characters/red_panda.png', 1, true)
ON CONFLICT (code) DO NOTHING;

-- ========== 아이템 그룹(소유·착용 단위) ==========
-- 상점·인벤토리·착용이 다루는 유일한 단위. 캐릭터별 이미지 차이는 character_items 가 흡수한다.
CREATE TABLE item_groups (
    code          VARCHAR(40) PRIMARY KEY,                  -- OUTFIT_BASIC_TEE 등 (FK 대상)
    slot          VARCHAR(20) NOT NULL,                     -- HAT/OUTFIT/GLASSES/PROP/ROOM_PROP/BACKGROUND
    name_ko       VARCHAR(50) NOT NULL,
    thumbnail_url TEXT NOT NULL,                            -- 상점·옷장 목록용 대표 썸네일(assets/items/*)
    acquire_type  VARCHAR(20) NOT NULL,                     -- DEFAULT(기본 제공)/MISSION(미션 해금)/COIN(구매)
    coin_price    INT NOT NULL DEFAULT 0,                   -- COIN 전용 가격(그 외 0)
    sort_order    INT NOT NULL DEFAULT 0,
    active        BOOLEAN NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_item_groups_slot
        CHECK (slot IN ('HAT','OUTFIT','GLASSES','PROP','ROOM_PROP','BACKGROUND')),
    CONSTRAINT chk_item_groups_acquire
        CHECK (acquire_type IN ('DEFAULT','MISSION','COIN')),
    -- 가격 정합: 구매형이면 양수 가격 필수, 그 외(기본·미션 해금)는 0 고정.
    -- 상점에 "0코인 상품"이나 "가격표 붙은 미션 보상"이 섞이는 걸 DB에서 차단한다.
    CONSTRAINT chk_item_groups_price
        CHECK ((acquire_type = 'COIN' AND coin_price > 0)
            OR (acquire_type <> 'COIN' AND coin_price = 0))
);

-- 상점·옷장 슬롯별 목록 조회(활성 행 한정).
CREATE INDEX idx_item_groups_slot ON item_groups (slot, sort_order) WHERE active;

-- ========== 캐릭터별 렌더 variant ==========
-- character_code NOT NULL = 캐릭터 전용(HAT/OUTFIT/GLASSES/PROP — 체형·머리 크기 차이로 PNG 분리)
-- character_code NULL     = 공용(ROOM_PROP/BACKGROUND — 캐릭터 옆·뒤라 체형 무관)
CREATE TABLE character_items (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    group_code     VARCHAR(40) NOT NULL REFERENCES item_groups(code) ON DELETE CASCADE,
    character_code VARCHAR(30) REFERENCES characters(code) ON DELETE CASCADE,  -- NULL=공용 variant
    image_url      TEXT NOT NULL,                           -- 앱 로컬 에셋 경로(assets/items/*)
    rive_slot      VARCHAR(20),                             -- Rive VM 이미지 프로퍼티명(hat/outfit/.../roomProp0..5)
    render_meta    JSONB,                                   -- 플레이스홀더 렌더러(Task 029) 전용
                                                            -- {"anchorX":0.5,"anchorY":0.18,"scale":0.42,"z":30}
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- ★ (group, 캐릭터) 당 variant 1행.
    --   일반 UNIQUE 는 NULL 을 서로 '구별되는 값'으로 취급해 공용 variant(character_code IS NULL)의
    --   중복 행을 막지 못한다. PG15+ 의 NULLS NOT DISTINCT 로 NULL 도 같은 값으로 보게 해
    --   "공용 variant 도 group 당 정확히 1행" 을 단일 제약으로 강제한다(운영 PG18).
    --   대안(부분 유니크 인덱스 2개: character_code IS NULL / IS NOT NULL)보다 제약 1개로 끝나 단순하다.
    CONSTRAINT uq_variant UNIQUE NULLS NOT DISTINCT (group_code, character_code)
);

-- variant 해석 경로: (선택 캐릭터 + 공용) 을 한 번에 긁는 조회.
CREATE INDEX idx_character_items_character ON character_items (character_code, group_code);

-- ========== 캐릭터 대사(맥락 기반) ==========
-- context 는 '감정'이 아니라 '맥락'이다(감정 규칙은 캐릭터 도메인에 없음).
-- character_code NULL = 공용 대사(캐릭터 미선택·폴백 시 사용).
CREATE TABLE character_lines (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    character_code VARCHAR(30) REFERENCES characters(code) ON DELETE CASCADE,  -- NULL=공용 대사
    context        VARCHAR(20) NOT NULL,                    -- CONFIRM/STREAK_3/STREAK_7/MISSION/LEVEL_UP/IDLE
    line_ko        VARCHAR(120) NOT NULL,                   -- 대사 본문(리액션 payload 에 실려 앱이 표시)
    rive_trigger   VARCHAR(40),                             -- 함께 재생할 Rive 트리거명(NULL=기본 모션)
    weight         INT NOT NULL DEFAULT 1,                  -- 가중 랜덤 선택(클수록 자주 뽑힘)
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_character_lines_context
        CHECK (context IN ('CONFIRM','STREAK_3','STREAK_7','MISSION','LEVEL_UP','IDLE')),
    CONSTRAINT chk_character_lines_weight CHECK (weight > 0)
);

-- 대사 선택(Task 028 LineService): (캐릭터, 맥락) 등치 조회 + 공용 폴백.
CREATE INDEX idx_character_lines_ctx ON character_lines (context, character_code);

-- ========== 대사 시드 ==========
-- 원숭이: 느긋한 말투("천천히", "괜찮아", 여유). 레서판다: 애쓰는 말투("열심히", "챙겼어", 밀착).
-- 공용(NULL): 캐릭터 미선택 상태·폴백용 중립 톤.
INSERT INTO character_lines (character_code, context, line_ko, rive_trigger, weight) VALUES
    -- ---------- 원숭이(여유·느긋) ----------
    ('MONKEY', 'CONFIRM',  '오늘도 한 줄 남겼네. 천천히 해도 다 남더라.',        'nod',     2),
    ('MONKEY', 'CONFIRM',  '잘 썼어. 이제 좀 늘어져도 되는 시간이야.',            'relax',   1),
    ('MONKEY', 'CONFIRM',  '급할 것 없지. 오늘 몫은 오늘로 충분해.',              NULL,      1),
    ('MONKEY', 'STREAK_3', '3일이나 왔네? 나는 세는 것도 잊고 있었는데.',          'clap',    2),
    ('MONKEY', 'STREAK_3', '3일 연속이라니. 이 정도면 낮잠 한 판 자도 되겠다.',    'relax',   1),
    ('MONKEY', 'STREAK_7', '일주일이 그냥 흘러갔네. 너답게 편안하게 왔어.',        'cheer',   2),
    ('MONKEY', 'STREAK_7', '7일. 애쓴 티도 안 나게 해내는 게 네 스타일이야.',      NULL,      1),
    ('MONKEY', 'MISSION',  '어쩌다 보니 미션도 끝났네. 축하해, 느긋하게 즐겨.',    'cheer',   2),
    ('MONKEY', 'MISSION',  '미션 완료. 상은 챙겨두고, 우린 좀 쉬자.',              NULL,      1),
    ('MONKEY', 'LEVEL_UP', '레벨이 올랐대. 뭐, 서두른 적도 없는데 말이야.',        'levelup', 2),
    ('MONKEY', 'LEVEL_UP', '한 단계 올라왔어. 계단은 천천히 오르는 게 제맛이지.',  'levelup', 1),
    ('MONKEY', 'IDLE',     '음… 오늘은 뭐 하지. 일단 좀 늘어져 볼까.',             'relax',   2),
    ('MONKEY', 'IDLE',     '기다리는 것도 쉬는 거야. 편할 때 와.',                 NULL,      1),
    -- ---------- 레서판다(부지런·애착) ----------
    ('RED_PANDA', 'CONFIRM',  '오늘 것도 잘 챙겼어! 하나도 안 흘렸어.',              'nod',     2),
    ('RED_PANDA', 'CONFIRM',  '기다리고 있었어. 네 하루, 내가 잘 보관해 둘게.',      'hug',     2),
    ('RED_PANDA', 'CONFIRM',  '오늘도 와줘서 고마워. 진짜로.',                       NULL,      1),
    ('RED_PANDA', 'STREAK_3', '3일 연속이야! 내가 하루하루 세고 있었어.',            'clap',    2),
    ('RED_PANDA', 'STREAK_3', '삼일이나 지켰어. 나 지금 좀 뿌듯한데?',               'cheer',   1),
    ('RED_PANDA', 'STREAK_7', '7일 완주! 하루도 안 빼먹었어, 내가 다 봤어.',         'cheer',   2),
    ('RED_PANDA', 'STREAK_7', '일주일이야. 이 정도면 나 자랑하고 다녀도 되지?',      'clap',    1),
    ('RED_PANDA', 'MISSION',  '미션 성공! 이거 받으려고 얼마나 열심히 했는데.',      'cheer',   2),
    ('RED_PANDA', 'MISSION',  '해냈어! 보상은 내가 꼭 챙겨왔어.',                    NULL,      1),
    ('RED_PANDA', 'LEVEL_UP', '레벨 업! 우리 같이 큰 거야, 같이!',                   'levelup', 2),
    ('RED_PANDA', 'LEVEL_UP', '한 단계 올랐어. 더 잘 챙겨줄 수 있겠다.',             'levelup', 1),
    ('RED_PANDA', 'IDLE',     '언제 오나 하고 계속 보고 있었어.',                    'hug',     2),
    ('RED_PANDA', 'IDLE',     '오늘도 여기 있을게. 짧게라도 들러줘.',                NULL,      1),
    -- ---------- 공용(캐릭터 미선택·폴백) ----------
    (NULL, 'CONFIRM',  '오늘의 기록이 저장됐어요.',            NULL, 1),
    (NULL, 'CONFIRM',  '한 페이지가 채워졌어요.',              NULL, 1),
    (NULL, 'STREAK_3', '3일 연속 기록했어요.',                 NULL, 1),
    (NULL, 'STREAK_7', '7일 연속 기록했어요.',                 NULL, 1),
    (NULL, 'MISSION',  '미션을 달성했어요.',                   NULL, 1),
    (NULL, 'LEVEL_UP', '레벨이 올랐어요.',                     NULL, 1),
    (NULL, 'IDLE',     '오늘 하루는 어땠나요?',                NULL, 1);

-- ========== 아이템 시드 ==========
-- 기본 제공(DEFAULT) + 미션 보상(MISSION, V16 이 참조) + 구매(COIN, Task 028 상점 검증용).
INSERT INTO item_groups (code, slot, name_ko, thumbnail_url, acquire_type, coin_price, sort_order) VALUES
    ('OUTFIT_BASIC_TEE', 'OUTFIT',     '기본 흰 티셔츠', 'assets/items/outfit_basic_tee.png', 'DEFAULT',   0,  0),
    ('ROOM_PROP_PLANT',  'ROOM_PROP',  '작은 화분',      'assets/items/room_prop_plant.png',  'DEFAULT',   0, 10),
    ('HAT_PARTY',        'HAT',        '파티 모자',      'assets/items/hat_party.png',        'MISSION',   0, 20),
    ('BG_COZY_ROOM',     'BACKGROUND', '아늑한 방',      'assets/items/bg_cozy_room.png',     'MISSION',   0, 30),
    ('HAT_STRAW',        'HAT',        '밀짚모자',       'assets/items/hat_straw.png',        'COIN',    120, 40)
ON CONFLICT (code) DO NOTHING;

-- variant 시드.
-- 착용 아이템(OUTFIT/HAT)은 캐릭터별 2행(체형 차이 → 별도 PNG),
-- 방 소품·배경(ROOM_PROP/BACKGROUND)은 공용 1행(character_code NULL).
INSERT INTO character_items (group_code, character_code, image_url, rive_slot, render_meta) VALUES
    ('OUTFIT_BASIC_TEE', 'MONKEY',    'assets/items/outfit_basic_tee_monkey.png',    'outfit',
     '{"anchorX":0.5,"anchorY":0.55,"scale":0.60,"z":30}'),
    ('OUTFIT_BASIC_TEE', 'RED_PANDA', 'assets/items/outfit_basic_tee_red_panda.png', 'outfit',
     '{"anchorX":0.5,"anchorY":0.58,"scale":0.66,"z":30}'),   -- 통통한 체형 → scale·anchorY 보정
    ('HAT_PARTY',        'MONKEY',    'assets/items/hat_party_monkey.png',           'hat',
     '{"anchorX":0.5,"anchorY":0.18,"scale":0.42,"z":40}'),
    ('HAT_PARTY',        'RED_PANDA', 'assets/items/hat_party_red_panda.png',        'hat',
     '{"anchorX":0.5,"anchorY":0.16,"scale":0.48,"z":40}'),   -- 머리가 커서 모자도 크게
    ('HAT_STRAW',        'MONKEY',    'assets/items/hat_straw_monkey.png',           'hat',
     '{"anchorX":0.5,"anchorY":0.18,"scale":0.44,"z":40}'),
    ('HAT_STRAW',        'RED_PANDA', 'assets/items/hat_straw_red_panda.png',        'hat',
     '{"anchorX":0.5,"anchorY":0.16,"scale":0.50,"z":40}'),
    -- 공용 variant(character_code NULL): 캐릭터 무관하게 해석된다.
    ('ROOM_PROP_PLANT',  NULL,        'assets/items/room_prop_plant.png',            'roomProp0',
     '{"anchorX":0.82,"anchorY":0.78,"scale":0.30,"z":10}'),
    ('BG_COZY_ROOM',     NULL,        'assets/items/bg_cozy_room.png',               'background',
     '{"anchorX":0.5,"anchorY":0.5,"scale":1.0,"z":0}');
