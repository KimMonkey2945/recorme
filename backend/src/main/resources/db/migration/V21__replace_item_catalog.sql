-- =====================================================================
-- V21__replace_item_catalog.sql — 옷장 아이템 카탈로그 5종 교체
-- 원본: 사용자 지정(docs/recormeImo/item), tasks/030
--
-- 옷장을 실사 에셋 5종(모자·안경·상의·하의·신발)만 남기도록 정리한다. V15 시드 아이템은 전부 제거하고,
-- 5종은 코인 경제의 첫 **구매 대상**(acquire_type=COIN)으로 등록한다 — 구매 기능(Task 028 잔여) 구현 전까지는
-- 미보유(잠금) 상태로 가격만 노출된다. 에셋(캐릭터별 투명 PNG)은 app/assets/items 에 이미 존재한다.
--
-- ⚠️ DEFAULT 아이템이 0개가 되므로 grantDefaultItemGroups(JIT)는 아무것도 지급하지 않는다 →
--    신규 유저는 빈 옷장(전부 잠금)으로 시작한다. 캐릭터 본체는 통짜 PNG라 아이템 없이도 정상 렌더된다.
-- =====================================================================

-- 1) 미션 아이템 보상 FK 해제 --------------------------------------------------
-- 삭제 대상(HAT_PARTY·BG_COZY_ROOM)을 missions.item_group_reward 가 RESTRICT FK 로 참조 중이므로 먼저 NULL 로 푼다.
-- 두 미션의 coin_reward 가 양수(50/100)라 chk_missions_reward(코인>0 OR 아이템 NOT NULL)는 그대로 통과한다.
-- (미션 아이템 지급은 보상 재설계로 미구현이므로 NULL 정리가 방향과 일치한다.)
UPDATE missions SET item_group_reward = NULL WHERE code IN ('DIARY_10', 'STREAK_7');

-- 2) 슬롯 CHECK 확장: BOTTOM·SHOES 추가 ---------------------------------------
-- 부위별 착용(하의·신발)을 서버에서도 허용하도록 두 CHECK 를 재정의한다(V18 의 CHECK 재정의 패턴).
ALTER TABLE item_groups DROP CONSTRAINT IF EXISTS chk_item_groups_slot;
ALTER TABLE item_groups ADD CONSTRAINT chk_item_groups_slot
    CHECK (slot IN ('HAT','OUTFIT','GLASSES','BOTTOM','SHOES','PROP','ROOM_PROP','BACKGROUND'));

ALTER TABLE user_equipment DROP CONSTRAINT IF EXISTS chk_user_equipment_slot;
ALTER TABLE user_equipment ADD CONSTRAINT chk_user_equipment_slot
    CHECK (slot IN ('HAT','OUTFIT','GLASSES','BOTTOM','SHOES','PROP','ROOM_PROP','BACKGROUND'));

-- 3) 기존 카탈로그 삭제 --------------------------------------------------------
-- character_items(group_code CASCADE)·user_item_groups(CASCADE)·user_equipment(2단 CASCADE)가 자동 정리된다.
DELETE FROM item_groups
 WHERE code IN ('OUTFIT_BASIC_TEE', 'ROOM_PROP_PLANT', 'HAT_PARTY', 'BG_COZY_ROOM', 'HAT_STRAW');

-- 4) 신규 5종 INSERT (전부 COIN — 가격은 사용자 지정) ---------------------------
-- chk_item_groups_price: COIN 이면 coin_price>0 필수(전부 충족).
INSERT INTO item_groups (code, slot, name_ko, thumbnail_url, acquire_type, coin_price, sort_order) VALUES
    ('HAT_CAP_BLACK',     'HAT',     '누구나 소화할 수 있는 검은색 캡모자',                          'assets/items/hat_cap_black.png',     'COIN', 15, 10),
    ('GLASSES_ROUND',     'GLASSES', '안경알은 없지만 멋짐을 위한 검은색 뿔테안경',                    'assets/items/glasses_round.png',     'COIN', 15, 20),
    ('OUTFIT_LOVE_HOOD',  'OUTFIT',  '사랑하는 사람에게 보여주고 싶은 낭낭한 후드티',                  'assets/items/outfit_love_hood.png',  'COIN', 50, 30),
    ('BOTTOM_CARGO_SAND', 'BOTTOM',  '입으면 사막에서도 살아남을 것 같은 바지',                        'assets/items/bottom_cargo_sand.png', 'COIN', 50, 40),
    ('SHOES_MAX95',       'SHOES',   '신발에 에어가 없으면 허리가 아픈 사람을 위한 에어빵빵 신발',       'assets/items/shoes_max95.png',       'COIN', 20, 50);

-- variant: 5종 모두 캐릭터별 2행(체형·머리 크기 차이로 PNG 분리). render_meta/rive_slot 는 앱 렌더러 튜닝값과 동일.
INSERT INTO character_items (group_code, character_code, image_url, rive_slot, render_meta) VALUES
    ('HAT_CAP_BLACK',     'MONKEY',    'assets/items/hat_cap_black_monkey.png',       'hat',
     '{"anchorX":0.5,"anchorY":0.18,"scale":0.42,"z":40}'),
    ('HAT_CAP_BLACK',     'RED_PANDA', 'assets/items/hat_cap_black_red_panda.png',    'hat',
     '{"anchorX":0.5,"anchorY":0.16,"scale":0.48,"z":40}'),
    ('GLASSES_ROUND',     'MONKEY',    'assets/items/glasses_round_monkey.png',       'glasses',
     '{"anchorX":0.5,"anchorY":0.27,"scale":0.40,"z":35}'),
    ('GLASSES_ROUND',     'RED_PANDA', 'assets/items/glasses_round_red_panda.png',    'glasses',
     '{"anchorX":0.5,"anchorY":0.26,"scale":0.42,"z":35}'),
    ('OUTFIT_LOVE_HOOD',  'MONKEY',    'assets/items/outfit_love_hood_monkey.png',    'outfit',
     '{"anchorX":0.5,"anchorY":0.6,"scale":0.8,"z":30}'),
    ('OUTFIT_LOVE_HOOD',  'RED_PANDA', 'assets/items/outfit_love_hood_red_panda.png', 'outfit',
     '{"anchorX":0.5,"anchorY":0.6,"scale":0.8,"z":30}'),
    ('BOTTOM_CARGO_SAND', 'MONKEY',    'assets/items/bottom_cargo_sand_monkey.png',   'bottom',
     '{"anchorX":0.5,"anchorY":0.75,"scale":0.6,"z":28}'),
    ('BOTTOM_CARGO_SAND', 'RED_PANDA', 'assets/items/bottom_cargo_sand_red_panda.png','bottom',
     '{"anchorX":0.5,"anchorY":0.75,"scale":0.6,"z":28}'),
    ('SHOES_MAX95',       'MONKEY',    'assets/items/shoes_max95_monkey.png',         'shoes',
     '{"anchorX":0.5,"anchorY":0.93,"scale":0.5,"z":26}'),
    -- 판다는 하의가 하반신 통째 교체(맨발 포함)라 신발을 그 위(z 29)로 올린다.
    ('SHOES_MAX95',       'RED_PANDA', 'assets/items/shoes_max95_red_panda.png',      'shoes',
     '{"anchorX":0.5,"anchorY":0.93,"scale":0.5,"z":29}');
