package com.recordapp.infra.push;

import java.util.List;

/**
 * 푸시 발송 결과. 부분 성공을 표현한다(멀티캐스트라 토큰별 성패가 갈릴 수 있음).
 *
 * @param successCount  발송 성공한 토큰 수
 * @param invalidTokens 영구 무효 토큰 목록(UNREGISTERED/INVALID_ARGUMENT). 상위 호출자가 DB에서 회수한다.
 *                      일시 오류(네트워크·쿼터 등)는 토큰을 보존하므로 여기 포함하지 않는다.
 */
public record PushResult(int successCount, List<String> invalidTokens) {
}
