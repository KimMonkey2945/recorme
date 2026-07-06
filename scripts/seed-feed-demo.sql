-- =====================================================================
-- seed-feed-demo.sql — 피드 데모용 더미 데이터(멱등, 로컬 전용)
-- 더미 사용자 3명 + 각자의 PUBLIC·DONE 일기 + 상호 공감을 넣어,
-- 어떤 계정으로 로그인해도 피드 탭에 감정 카드가 즉시 보이게 한다(PUBLIC이라 전원 노출).
-- 재실행 안전(ON CONFLICT DO NOTHING + 카운트 재계산). 운영 DB에는 절대 실행 금지.
--   실행: psql -h localhost -p 5432 -U recorme -d recorme -v ON_ERROR_STOP=1 -f scripts/seed-feed-demo.sql
--   제거: 하단 "제거" 블록 주석 해제 후 실행.
-- =====================================================================

-- ── 더미 사용자(고정 supabase_uid로 멱등) ──
INSERT INTO users (supabase_uid, nickname, email, bio, friend_code) VALUES
  ('11111111-1111-4111-8111-111111111111', '달빛산책',  'demo.dalbit@example.com',  '밤 산책을 좋아해요',   'DALBIT01'),
  ('22222222-2222-4222-8222-222222222222', '노을수집가', 'demo.noeul@example.com',   '노을 사진을 모아요',   'NOEUL002'),
  ('33333333-3333-4333-8333-333333333333', '차분한새벽', 'demo.saebyeok@example.com', '새벽의 고요를 씁니다', 'SAEBYK03')
ON CONFLICT (supabase_uid) DO NOTHING;

-- ── PUBLIC·DONE 일기(작성자별 서로 다른 날짜로 하루1기록 유니크 충족) ──
-- 색은 앱이 DiaryTheme.fromEmotion으로 재계산하므로 형식만 맞으면 됨(#RRGGBB).
INSERT INTO diaries (user_id, content, content_text, written_date, visibility, analysis_status,
                     primary_emotion, background_color, text_color, accent_color,
                     ai_comment, ai_title, mood_emoji, analyzed_at)
SELECT u.id, d.content, d.content_text, d.written_date, 'PUBLIC', 'DONE',
       d.emotion, d.bg, d.tc, d.ac, d.comment, d.title, d.emoji, now()
FROM (VALUES
  ('11111111-1111-4111-8111-111111111111'::uuid,
   '{"ops":[{"insert":"골목 끝에서 만난 고양이가 한참 나를 따라왔다. 별거 아닌데 하루가 환해졌다.\n"}]}',
   '골목 끝에서 만난 고양이가 한참 나를 따라왔다. 별거 아닌데 하루가 환해졌다.',
   CURRENT_DATE - 1, 'JOY', '#FFF3D6', '#3A2E12', '#F5A623',
   '작은 마주침이 하루를 환하게 물들였네요.', '골목 고양이와의 오후', '😊'),
  ('11111111-1111-4111-8111-111111111111'::uuid,
   '{"ops":[{"insert":"오래 미뤄둔 책을 끝냈다. 마지막 장을 덮고 창밖을 오래 바라봤다.\n"}]}',
   '오래 미뤄둔 책을 끝냈다. 마지막 장을 덮고 창밖을 오래 바라봤다.',
   CURRENT_DATE - 3, 'CALM', '#E2F1E8', '#1C2B22', '#4CA06A',
   '고요히 마무리한 하루의 여운이 느껴져요.', '마지막 장을 덮으며', '😌'),
  ('22222222-2222-4222-8222-222222222222'::uuid,
   '{"ops":[{"insert":"괜히 마음이 가라앉는 날. 그래도 노을은 어김없이 예뻤다.\n"}]}',
   '괜히 마음이 가라앉는 날. 그래도 노을은 어김없이 예뻤다.',
   CURRENT_DATE - 1, 'SADNESS', '#E3EDF7', '#1F2A37', '#4A77B5',
   '가라앉은 마음 곁에도 예쁜 순간이 있었네요.', '그럼에도 노을은', '😔'),
  ('22222222-2222-4222-8222-222222222222'::uuid,
   '{"ops":[{"insert":"내일 발표가 자꾸 머릿속을 맴돈다. 심호흡을 여러 번 했다.\n"}]}',
   '내일 발표가 자꾸 머릿속을 맴돈다. 심호흡을 여러 번 했다.',
   CURRENT_DATE - 4, 'ANXIETY', '#ECE6F6', '#25203A', '#7A5AC2',
   '긴장 속에서도 스스로를 다독인 하루였어요.', '심호흡, 다시 한 번', '😟'),
  ('33333333-3333-4333-8333-333333333333'::uuid,
   '{"ops":[{"insert":"버스가 눈앞에서 떠났다. 사소한 일에 오래 짜증이 났다.\n"}]}',
   '버스가 눈앞에서 떠났다. 사소한 일에 오래 짜증이 났다.',
   CURRENT_DATE - 1, 'ANGER', '#FBE3DE', '#3A1A14', '#D64531',
   '작은 일에도 크게 흔들린 하루, 수고했어요.', '떠난 버스 앞에서', '😤'),
  ('33333333-3333-4333-8333-333333333333'::uuid,
   '{"ops":[{"insert":"새벽 다섯 시의 공기가 좋아서 일부러 일찍 나왔다. 조용한 거리.\n"}]}',
   '새벽 다섯 시의 공기가 좋아서 일부러 일찍 나왔다. 조용한 거리.',
   CURRENT_DATE - 2, 'JOY', '#FFF3D6', '#3A2E12', '#F5A623',
   '이른 새벽을 즐기는 마음이 반짝였어요.', '새벽 다섯 시의 거리', '😊')
) AS d(uid, content, content_text, written_date, emotion, bg, tc, ac, comment, title, emoji)
JOIN users u ON u.supabase_uid = d.uid
ON CONFLICT (user_id, written_date) WHERE deleted_at IS NULL DO NOTHING;

-- ── 더미끼리 상호 공감(각 PUBLIC 일기에 다른 더미 2명이 공감 → reaction_count=2) ──
INSERT INTO diary_reactions (diary_id, user_id, type)
SELECT d.id, ru.id, 'EMPATHY'
  FROM diaries d
  JOIN users au ON au.id = d.user_id
  JOIN users ru ON ru.id <> d.user_id
 WHERE au.supabase_uid IN ('11111111-1111-4111-8111-111111111111',
                           '22222222-2222-4222-8222-222222222222',
                           '33333333-3333-4333-8333-333333333333')
   AND ru.supabase_uid IN ('11111111-1111-4111-8111-111111111111',
                           '22222222-2222-4222-8222-222222222222',
                           '33333333-3333-4333-8333-333333333333')
   AND d.visibility = 'PUBLIC' AND d.analysis_status = 'DONE'
ON CONFLICT (diary_id, user_id, type) DO NOTHING;

-- ── 공감 수 캐시 재계산(멱등) ──
UPDATE diaries d
   SET reaction_count = (SELECT count(*) FROM diary_reactions r WHERE r.diary_id = d.id)
 WHERE d.user_id IN (SELECT id FROM users
                      WHERE supabase_uid IN ('11111111-1111-4111-8111-111111111111',
                                             '22222222-2222-4222-8222-222222222222',
                                             '33333333-3333-4333-8333-333333333333'));

-- ── 확인 ──
SELECT u.nickname, d.visibility, d.analysis_status, d.primary_emotion,
       d.reaction_count, d.written_date, d.ai_title
  FROM diaries d JOIN users u ON u.id = d.user_id
 WHERE u.supabase_uid IN ('11111111-1111-4111-8111-111111111111',
                          '22222222-2222-4222-8222-222222222222',
                          '33333333-3333-4333-8333-333333333333')
 ORDER BY u.nickname, d.written_date DESC;

-- ── 제거(필요 시 주석 해제) ──
-- DELETE FROM users WHERE supabase_uid IN
--   ('11111111-1111-4111-8111-111111111111',
--    '22222222-2222-4222-8222-222222222222',
--    '33333333-3333-4333-8333-333333333333');  -- diaries·reactions는 FK CASCADE로 함께 삭제
