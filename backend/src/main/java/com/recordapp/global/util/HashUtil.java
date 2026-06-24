package com.recordapp.global.util;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

/**
 * 해시 유틸. refresh 토큰은 평문 저장 대신 SHA-256 해시(hex)로 보관한다.
 */
public final class HashUtil {

	private HashUtil() {
	}

	/** SHA-256 해시를 소문자 hex 문자열(64자)로 반환 */
	public static String sha256Hex(String raw) {
		try {
			MessageDigest digest = MessageDigest.getInstance("SHA-256");
			byte[] hash = digest.digest(raw.getBytes(StandardCharsets.UTF_8));
			StringBuilder sb = new StringBuilder(hash.length * 2);
			for (byte b : hash) {
				sb.append(Character.forDigit((b >> 4) & 0xF, 16));
				sb.append(Character.forDigit(b & 0xF, 16));
			}
			return sb.toString();
		} catch (NoSuchAlgorithmException e) {
			// SHA-256은 모든 JVM이 보장하므로 발생하지 않음
			throw new IllegalStateException("SHA-256 미지원", e);
		}
	}
}
