package com.recordapp.global.util;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/**
 * HashUtil 단위 테스트(Docker 불필요).
 */
class HashUtilTest {

	@Test
	void sha256Hex_knownVector() {
		// "abc"의 SHA-256 표준 해시
		assertThat(HashUtil.sha256Hex("abc"))
				.isEqualTo("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
	}

	@Test
	void sha256Hex_is64HexChars() {
		String hash = HashUtil.sha256Hex("some-refresh-token");
		assertThat(hash).hasSize(64).matches("[0-9a-f]{64}");
	}

	@Test
	void sha256Hex_deterministic() {
		assertThat(HashUtil.sha256Hex("same")).isEqualTo(HashUtil.sha256Hex("same"));
	}
}
