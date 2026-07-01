package com.recordapp.infra.push;

import java.util.Map;

/**
 * 푸시 알림 메시지. provider 중립적인 표현으로, 발송 구현체({@link PushService})가 provider 포맷으로 변환한다.
 *
 * @param title 알림 제목(표시용)
 * @param body  알림 본문(표시용)
 * @param data  data 페이로드(딥링크·화면 라우팅 등 앱이 해석하는 key/value, null 가능)
 */
public record PushMessage(String title, String body, Map<String, String> data) {
}
