#version 460 core
#include <flutter/runtime_effect.glsl>

// 알파 매트 패킹 영상([좌: 캐릭터 색 | 우: 실루엣 알파], 2:1)을 받아
// 배경을 투명 처리해 캐릭터만 렌더한다.
//
// 입력 텍스처는 자식(VideoPlayer)을 캐릭터 종횡비 박스에 채워 래스터한 이미지다.
// 좌 절반(uv.x*0.5)에서 색을, 우 절반(0.5+uv.x*0.5)에서 알파(그레이 R채널)를 읽어
// premultiplied RGBA로 출력한다(가장자리 자연스러운 합성).

uniform vec2 uSize;       // 출력(캐릭터) 박스 크기(px)
uniform sampler2D uTex;   // 패킹 프레임 래스터

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;      // 0..1 (출력 박스 기준)
  vec3 rgb = texture(uTex, vec2(uv.x * 0.5, uv.y)).rgb;         // 좌 절반 = 색
  float a  = texture(uTex, vec2(0.5 + uv.x * 0.5, uv.y)).r;     // 우 절반 = 알파
  fragColor = vec4(rgb * a, a);                 // premultiplied alpha
}
