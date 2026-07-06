package com.recordapp.domain.social;

import java.security.SecureRandom;

/**
 * 친구코드 생성기. 혼동 문자(I, L, O, U)를 제외한 32진 알파벳에서 8자리 대문자 코드를 만든다.
 * (V11 마이그레이션의 백필 알파벳과 동일해야 한다.)
 *
 * <p>공간은 32^8 ≈ 1.1e12 로 충돌이 사실상 무시 가능하나, 최종 유일성은
 * {@code uq_users_friend_code} UNIQUE 인덱스가 보장하고 호출 측이 충돌 시 재생성한다.
 */
public final class FriendCodeGenerator {

	/** 혼동 문자(I, L, O, U) 제외 32진 알파벳(대문자 캐노니컬). */
	private static final char[] ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ".toCharArray();
	private static final int LENGTH = 8;
	private static final SecureRandom RANDOM = new SecureRandom();

	private FriendCodeGenerator() {
	}

	/** 8자리 친구코드 1개 생성. */
	public static String generate() {
		StringBuilder sb = new StringBuilder(LENGTH);
		for (int i = 0; i < LENGTH; i++) {
			sb.append(ALPHABET[RANDOM.nextInt(ALPHABET.length)]);
		}
		return sb.toString();
	}
}
