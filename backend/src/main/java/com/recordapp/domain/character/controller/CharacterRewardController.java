package com.recordapp.domain.character.controller;

import com.recordapp.domain.character.dto.AckRewardsResponse;
import com.recordapp.domain.character.dto.AttendanceResponse;
import com.recordapp.domain.character.dto.RewardResponse;
import com.recordapp.domain.character.dto.WalletResponse;
import com.recordapp.domain.character.service.CharacterRewardService;
import com.recordapp.global.common.ApiResponse;
import com.recordapp.global.common.CursorRequest;
import com.recordapp.global.common.PageResponse;
import com.recordapp.global.security.SecurityUser;
import java.time.LocalDate;
import java.time.ZoneId;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 코인 지갑·보상함·리액션·출석 API(보상 엔진 Task 028). 컨텍스트 경로(/api/v1) 하위 /characters.
 * 본인 식별은 인증 principal 의 userId 로만 수행한다(경로·바디에 사용자 식별자 없음 — IDOR 차단).
 *
 * <p>코인 <b>적립</b>은 기록 확정·작심삼일 진척 이벤트로 자동 발생한다(이 컨트롤러는 조회 + 출석만).
 * 상점 구매(코인 <b>소비</b>)는 아직 범위 밖이다(아이템 확정 후 추가).
 */
@RestController
@RequestMapping("/characters")
public class CharacterRewardController {

	/** 모든 날짜 판정 기준 타임존(출석 하루 1회 판정 — 서버 기본 타임존과 무관하게 KST 벽시계로 통일). */
	private static final ZoneId KST = ZoneId.of("Asia/Seoul");

	private final CharacterRewardService rewardService;

	public CharacterRewardController(CharacterRewardService rewardService) {
		this.rewardService = rewardService;
	}

	/** GET /characters/me/wallet — 코인 잔액 + 미확인 보상 수(홈 상단 배지). */
	@GetMapping("/me/wallet")
	public ApiResponse<WalletResponse> getWallet(@AuthenticationPrincipal SecurityUser principal) {
		return ApiResponse.ok(rewardService.getWallet(principal.userId()));
	}

	/** GET /characters/me/rewards — 미확인 보상함(커서 페이징, 최신순). */
	@GetMapping("/me/rewards")
	public ApiResponse<PageResponse<RewardResponse>> getRewards(
			@AuthenticationPrincipal SecurityUser principal,
			@RequestParam(required = false) Long cursor,
			@RequestParam(required = false) Integer size) {
		return ApiResponse.ok(rewardService.getRewards(principal.userId(), new CursorRequest(cursor, size)));
	}

	/** POST /characters/me/rewards/ack — 미확인 보상 전체 확인(뱃지 리셋). */
	@PostMapping("/me/rewards/ack")
	public ApiResponse<AckRewardsResponse> ackRewards(@AuthenticationPrincipal SecurityUser principal) {
		return ApiResponse.ok(rewardService.ackRewards(principal.userId()));
	}

	/**
	 * GET /characters/me/reaction?diaryId= — 확정 직후 리액션(폴링 불필요, 확정 즉시 생성).
	 * 아직 적립 이벤트가 생성되기 전이면 data=null 이다(앱은 생략하거나 잠깐 뒤 재조회).
	 */
	@GetMapping("/me/reaction")
	public ApiResponse<RewardResponse> getReaction(
			@AuthenticationPrincipal SecurityUser principal,
			@RequestParam long diaryId) {
		return ApiResponse.ok(rewardService.getReaction(principal.userId(), diaryId));
	}

	/**
	 * POST /characters/me/attendance — 출석 적립(하루 1회). 앱이 캐릭터 홈 진입 시 호출한다.
	 * granted=false 면 오늘 이미 출석했거나 출석 보상이 꺼진 것이다(잔액은 그대로 반환).
	 */
	@PostMapping("/me/attendance")
	public ApiResponse<AttendanceResponse> attendance(@AuthenticationPrincipal SecurityUser principal) {
		CharacterRewardService.AttendanceResult r =
				rewardService.grantAttendance(principal.userId(), LocalDate.now(KST));
		return ApiResponse.ok(new AttendanceResponse(r.granted(), r.coin(), r.balance()));
	}
}
