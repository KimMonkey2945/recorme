package com.recordapp.domain.emotion.mapper;

import com.recordapp.domain.emotion.dto.AnalysisTarget;
import java.util.List;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

/**
 * diaries 테이블의 감정 분석 컬럼 전용 매퍼(읽기 대상·결과 반영·폴러 백스톱).
 *
 * <p>DiaryMapper 와 분리한 이유: 분석은 비동기 스레드가 소유권(user_id) 없이 PK 로만 접근하며,
 * 결과 반영은 {@code analysis_status='PENDING'} + {@code content_text} 일치를 조건으로 하는
 * 멱등·낙관적 UPDATE 라 일기 CRUD 와 관심사가 다르다. ⚠️ 모든 UPDATE 는 {@code updated_at} 을
 * 건드리지 않는다(사용자 편집 시각 보존).
 */
@Mapper
public interface EmotionAnalysisMapper {

	/**
	 * 분석 대상 일기 스냅샷 조회. {@code PENDING} 이고 활성(미삭제)인 행만 반환한다.
	 * 이미 처리됐거나(DONE/FAILED) 삭제·재수정으로 상태가 바뀌면 null → 분석을 건너뛴다.
	 */
	AnalysisTarget findTarget(@Param("id") long id);

	/**
	 * 분석 결과를 DONE 으로 반영하는 조건부(낙관적) UPDATE.
	 * <p>WHERE 에 {@code analysis_status='PENDING'} 과 {@code content_text=#{analyzedText}} 를 두어,
	 * 분석 중 사용자가 본문을 수정·삭제했으면 0행을 반환(결과 폐기)한다. DONE 전이 시 primary_emotion 을
	 * 반드시 채워 V7 CHECK(chk_diaries_done_has_emotion)를 통과한다.
	 *
	 * @return 갱신 행 수(0이면 stale — 폐기)
	 */
	int updateResult(@Param("id") long id,
			@Param("analyzedText") String analyzedText,
			@Param("primaryEmotion") String primaryEmotion,
			@Param("backgroundColor") String backgroundColor,
			@Param("textColor") String textColor,
			@Param("accentColor") String accentColor,
			@Param("aiComment") String aiComment,
			@Param("aiTitle") String aiTitle,
			@Param("moodEmoji") String moodEmoji,
			@Param("emotionScoresJson") String emotionScoresJson);

	/**
	 * 예기치 못한 예외(이미지/직렬화/매퍼) 시 FAILED 로 반영하는 조건부 UPDATE.
	 * FAILED 여도 primary_emotion='NEUTRAL' 등 중립 팔레트를 채워 CHECK 통과 + 앱이 중립 렌더하게 한다.
	 * WHERE 조건은 updateResult 와 동일(stale 이면 0행).
	 *
	 * @return 갱신 행 수(0이면 stale)
	 */
	int updateFailed(@Param("id") long id, @Param("analyzedText") String analyzedText);

	/**
	 * 폴러 백스톱: 미처리(PENDING) 활성 일기 ID 를 id 오름차순으로 최대 limit 건 잠금 조회한다.
	 * {@code FOR UPDATE SKIP LOCKED} 로 다중 인스턴스·동시 폴링에서 같은 행을 중복 선점하지 않는다.
     * 호출자는 짧은 트랜잭션 안에서 dispatch 후 즉시 커밋해 잠금을 푼다(실제 LLM 은 잠금 밖).
	 */
	List<Long> findStalePendingIds(@Param("limit") int limit);
}
