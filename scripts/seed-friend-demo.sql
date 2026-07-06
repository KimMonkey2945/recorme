-- =====================================================================
-- seed-friend-demo.sql — 친구 흐름 혼자 시뮬레이션용(멱등, 로컬 전용)
-- 로그인한 내 계정과 더미 사이에 관계를 심어, 2계정 없이도 친구 기능을 체험한다:
--   ① 달빛산책 = 이미 수락된 친구(친구 목록·삭제/차단 테스트)
--   ② 노을수집가 = 나에게 보낸 '받은 요청' PENDING(요청함에서 수락/거절 테스트)
--   ③ 달빛산책의 FRIENDS 공개 일기 1건(친구 전용 피드 노출 테스트)
-- 선행: seed-feed-demo.sql 실행 + 앱에서 최소 1회 로그인(백엔드가 내 users 행을 JIT 생성).
-- 실행: psql ... -v ON_ERROR_STOP=1 -v email='내가로그인한이메일' -f scripts/seed-friend-demo.sql
-- =====================================================================

-- ① 달빛산책 → 나 : ACCEPTED (무방향 쌍 중복 방지 위해 NOT EXISTS 가드)
INSERT INTO friendships (requester_id, addressee_id, status, responded_at)
SELECT a.id, me.id, 'ACCEPTED', now()
  FROM users a, users me
 WHERE a.supabase_uid = '11111111-1111-4111-8111-111111111111'
   AND lower(me.email) = lower(:'email')
   AND NOT EXISTS (
       SELECT 1 FROM friendships f
        WHERE LEAST(f.requester_id, f.addressee_id) = LEAST(a.id, me.id)
          AND GREATEST(f.requester_id, f.addressee_id) = GREATEST(a.id, me.id));

-- ② 노을수집가 → 나 : PENDING(받은 요청)
INSERT INTO friendships (requester_id, addressee_id, status)
SELECT b.id, me.id, 'PENDING'
  FROM users b, users me
 WHERE b.supabase_uid = '22222222-2222-4222-8222-222222222222'
   AND lower(me.email) = lower(:'email')
   AND NOT EXISTS (
       SELECT 1 FROM friendships f
        WHERE LEAST(f.requester_id, f.addressee_id) = LEAST(b.id, me.id)
          AND GREATEST(f.requester_id, f.addressee_id) = GREATEST(b.id, me.id));

-- ③ 달빛산책의 FRIENDS 공개 일기(친구인 나에게만 피드 노출). 기존 더미 날짜와 겹치지 않게 D-2.
INSERT INTO diaries (user_id, content, content_text, written_date, visibility, analysis_status,
                     primary_emotion, background_color, text_color, accent_color,
                     ai_comment, ai_title, mood_emoji, analyzed_at)
SELECT a.id,
       '{"ops":[{"insert":"친구에게만 보여주고 싶은 하루. 오늘은 조금 특별했다.\n"}]}',
       '친구에게만 보여주고 싶은 하루. 오늘은 조금 특별했다.',
       CURRENT_DATE - 2, 'FRIENDS', 'DONE',
       'CALM', '#E2F1E8', '#1C2B22', '#4CA06A',
       '가까운 사람과 나누고 싶은 잔잔한 하루네요.', '친구에게만, 오늘', '😌', now()
  FROM users a
 WHERE a.supabase_uid = '11111111-1111-4111-8111-111111111111'
ON CONFLICT (user_id, written_date) WHERE deleted_at IS NULL DO NOTHING;

-- ── 확인 ──
SELECT '내 친구/요청' AS section, f.status,
       ra.nickname AS requester, ad.nickname AS addressee
  FROM friendships f
  JOIN users ra ON ra.id = f.requester_id
  JOIN users ad ON ad.id = f.addressee_id
  JOIN users me ON lower(me.email) = lower(:'email')
 WHERE me.id IN (f.requester_id, f.addressee_id)
 ORDER BY f.status;
