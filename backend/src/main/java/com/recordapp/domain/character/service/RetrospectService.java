package com.recordapp.domain.character.service;

import com.recordapp.domain.character.dto.EmotionCountRow;
import com.recordapp.domain.character.dto.EmotionStat;
import com.recordapp.domain.character.dto.ItemGroupRow;
import com.recordapp.domain.character.dto.MonthlyEventAggRow;
import com.recordapp.domain.character.dto.ResolvedVariant;
import com.recordapp.domain.character.dto.RetrospectResponse;
import com.recordapp.domain.character.dto.UnlockedItem;
import com.recordapp.domain.character.mapper.RetrospectMapper;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.YearMonth;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 월간 회고(Task 032 — 락인) 조회 서비스. 이달의 기록·연속일·감정 분포·획득 코인·획득 아이템을 한 장으로 집계한다.
 *
 * <p><b>데이터가 쌓일수록 떠나기 어려워지는 구조</b>를 가시화하는 지점이다. 성장은 코인·획득 아이템으로만 표현하며
 * (경험치/레벨은 보상 재설계로 폐기 — V18), 감정은 이 화면의 통계에만 쓰이는 순수 메타데이터다.
 *
 * <p>월 경계는 두 시간축을 각각 자른다: 기록(확정일·감정)은 {@code written_date}(DATE) 로, 보상(코인·완주)·획득
 * 아이템은 {@code TIMESTAMPTZ} 로 KST 벽시계 기준 [이달 1일 00:00, 다음달 1일 00:00) 반열림 구간을 쓴다.
 * 빈 달(기록 0건)도 예외 없이 모든 수치 0 + 빈 리스트로 정상 응답한다.
 */
@Service
public class RetrospectService {

	/** 월 경계 판정 기준 타임존(서버 기본 타임존과 무관하게 KST 벽시계로 통일 — 출석·리액션과 동일 규칙). */
	private static final ZoneId KST = ZoneId.of("Asia/Seoul");

	private final RetrospectMapper mapper;
	private final CharacterService characterService;
	private final CatalogCache catalog;

	public RetrospectService(RetrospectMapper mapper,
			CharacterService characterService,
			CatalogCache catalog) {
		this.mapper = mapper;
		this.characterService = characterService;
		this.catalog = catalog;
	}

	/**
	 * 월간 회고 조회. 소유·집계는 전부 인증 principal 의 {@code userId} 로만 좁힌다(IDOR 차단).
	 *
	 * @param yearMonth 대상 월(호출부가 이미 파싱해 넘긴 값)
	 */
	@Transactional // ensureState 가 상태 행을 INSERT(멱등) 하므로 read-write 여야 한다(getWallet 과 동일).
	public RetrospectResponse getRetrospect(long userId, YearMonth yearMonth) {
		characterService.ensureState(userId); // JIT(멱등) — 지갑·진척 행 보장, 신규 유저도 빈 회고 정상 응답

		LocalDate monthStart = yearMonth.atDay(1);
		LocalDate nextMonth = yearMonth.plusMonths(1).atDay(1);
		OffsetDateTime tsStart = monthStart.atStartOfDay(KST).toOffsetDateTime();
		OffsetDateTime tsNext = nextMonth.atStartOfDay(KST).toOffsetDateTime();

		List<LocalDate> confirmedDates = mapper.findConfirmedDates(userId, monthStart, nextMonth);
		List<EmotionStat> emotions = mapper.aggregateEmotions(userId, monthStart, nextMonth).stream()
				.map(this::toEmotionStat)
				.toList();
		MonthlyEventAggRow agg = mapper.aggregateEvents(userId, tsStart, tsNext);
		List<UnlockedItem> unlockedItems = resolveUnlockedItems(userId,
				mapper.findAcquiredGroupCodes(userId, tsStart, tsNext));

		return new RetrospectResponse(
				yearMonth.toString(),
				confirmedDates.size(),
				maxConsecutiveDays(confirmedDates),
				agg.resolutionSuccessCount(),
				emotions,
				agg.coinEarned(),
				unlockedItems);
	}

	/** 프리셋(code 존재) vs 직접 입력(label 만) 구분해 응답 형태를 결정한다. */
	private EmotionStat toEmotionStat(EmotionCountRow row) {
		return row.code() != null
				? EmotionStat.preset(row.code(), row.labelKo(), row.count())
				: EmotionStat.custom(row.label(), row.count());
	}

	/**
	 * 오름차순·유일한 날짜 목록에서 달력상 연속(직전일 +1)인 최장 구간 길이를 센다.
	 * 하루라도 건너뛰면 1부터 다시 센다. 빈 목록은 0.
	 */
	private int maxConsecutiveDays(List<LocalDate> dates) {
		if (dates.isEmpty()) {
			return 0;
		}
		int max = 1;
		int current = 1;
		for (int i = 1; i < dates.size(); i++) {
			if (dates.get(i).equals(dates.get(i - 1).plusDays(1))) {
				current++;
			} else {
				current = 1;
			}
			max = Math.max(max, current);
		}
		return max;
	}

	/**
	 * 획득한 group 코드를 내 캐릭터 기준 이미지·이름으로 해석한다. 카탈로그에서 사라진(비활성) group 은 건너뛴다.
	 * variant 가 아직 없으면 이미지 null 로 담아 회고가 깨지지 않게 한다(획득 사실 자체는 보여 준다).
	 */
	private List<UnlockedItem> resolveUnlockedItems(long userId, List<String> groupCodes) {
		if (groupCodes.isEmpty()) {
			return List.of();
		}
		String selected = characterService.selectedCharacterOf(userId);
		List<UnlockedItem> items = new ArrayList<>(groupCodes.size());
		for (String code : groupCodes) {
			ItemGroupRow group = catalog.itemGroup(code);
			if (group == null) {
				continue;
			}
			ResolvedVariant variant = catalog.resolveVariant(code, selected);
			items.add(new UnlockedItem(code, group.nameKo(), variant == null ? null : variant.imageUrl()));
		}
		return items;
	}
}
