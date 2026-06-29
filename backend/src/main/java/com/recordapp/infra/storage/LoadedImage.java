package com.recordapp.infra.storage;

/**
 * 스토리지에서 읽어들인 이미지(원본 bytes + MIME). LLM 비전 입력 등에 사용한다.
 * 다운스케일은 호출자 책임 — 여기서는 디스크의 원본 bytes를 그대로 담는다.
 *
 * @param data      이미지 바이너리
 * @param mediaType MIME 타입(예: "image/jpeg", "image/png", "image/webp")
 */
public record LoadedImage(byte[] data, String mediaType) {
}
