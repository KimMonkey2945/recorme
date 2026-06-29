package com.recordapp.infra.llm;

/**
 * LLM 비전 입력으로 전달할 단일 이미지(원본 bytes).
 *
 * @param data      이미지 바이너리(다운스케일은 호출자 책임 — 여기서는 원본 그대로)
 * @param mediaType MIME 타입(예: "image/jpeg", "image/png", "image/webp")
 */
public record LlmImage(byte[] data, String mediaType) {
}
