package com.recordapp.domain.resolution.dto;

import java.time.LocalDate;
import java.time.LocalTime;

/**
 * 결심 INSERT 입력/출력 겸용 명령 객체. 생성(첫 도전)과 연장(다음 3일) 양쪽에서 쓴다.
 * <p>MyBatis 가 RETURNING id 를 useGeneratedKeys 로 회수하기 위해 가변 객체로 둔다
 * ({@code record} 는 setter 가 없어 keyProperty 회수가 불가하므로 가변 클래스 사용 — DiaryUpsertCommand 와 동일 관례).
 *
 * <p>{@code streakGroupId} 가 null 이면 첫 도전 → SQL 이 {@code gen_random_uuid()} 로 새 체인을 만든다.
 * 연장 시에는 이전 결심의 group 을 그대로 전달한다. {@code streakSeq} 는 첫 도전 1, 연장 시 prev+1.
 */
public class ResolutionInsertCommand {

	// ===== 입력 =====
	private final Long userId;
	private final String title;
	private final LocalDate startDate;
	private final LocalDate endDate;      // = startDate + (DURATION_DAYS - 1)
	private final LocalTime reminderTime; // nullable
	private final String streakGroupId;   // nullable — null 이면 SQL 에서 gen_random_uuid()
	private final Short streakSeq;        // 첫 도전 1, 연장 시 prev+1

	// ===== 출력(MyBatis keyProperty 회수 대상) =====
	private Long id;

	public ResolutionInsertCommand(Long userId, String title, LocalDate startDate, LocalDate endDate,
			LocalTime reminderTime, String streakGroupId, Short streakSeq) {
		this.userId = userId;
		this.title = title;
		this.startDate = startDate;
		this.endDate = endDate;
		this.reminderTime = reminderTime;
		this.streakGroupId = streakGroupId;
		this.streakSeq = streakSeq;
	}

	public Long getUserId() {
		return userId;
	}

	public String getTitle() {
		return title;
	}

	public LocalDate getStartDate() {
		return startDate;
	}

	public LocalDate getEndDate() {
		return endDate;
	}

	public LocalTime getReminderTime() {
		return reminderTime;
	}

	public String getStreakGroupId() {
		return streakGroupId;
	}

	public Short getStreakSeq() {
		return streakSeq;
	}

	public Long getId() {
		return id;
	}

	public void setId(Long id) {
		this.id = id;
	}
}
