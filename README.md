<div align="center">

# 📔 record

**하루를 기록하고, 나와 다른 사람의 하루를 서로 공유하는 모바일 앱**

<br/>

![Java](https://img.shields.io/badge/Java-007396?style=for-the-badge&logo=openjdk&logoColor=white)
![Spring Boot](https://img.shields.io/badge/Spring%20Boot-6DB33F?style=for-the-badge&logo=springboot&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)

</div>

---

## 📖 프로젝트 개요

`record`는 **매일의 하루를 글로 기록**하고, **나와 다른 사람의 하루를 서로 공유**할 수 있는 모바일 애플리케이션입니다.

단순한 일기를 넘어, 작성한 글의 **감정을 분석**하여 그날의 기분에 어울리는 테마(배경·필체)와 음악을 자동으로 입혀, 기록을 다시 볼 때 그날의 분위기를 그대로 느낄 수 있도록 합니다.

<br/>

## ✨ 주요 기능

### 1. 📝 하루 기록
- 그날의 하루를 글로 자유롭게 기록합니다.

### 2. 🎨 감정 기반 테마
- 작성한 글을 분석하여 당시의 **기분에 맞는 테마를 자동 설정**합니다.
- 기분에 따라 글의 **배경과 필체**를 다르게 적용하며, 조회 시 해당 테마가 반영되어 표시됩니다.

### 3. 🎵 감정 기반 음악
- 분석된 기분에 어울리는 **음악을 자동으로 설정**하여, 기록을 볼 때 함께 감상할 수 있습니다.

<br/>

## 🛠️ 기술 스택

| 구분 | 기술 |
| --- | --- |
| **Backend** | ![Java](https://img.shields.io/badge/Java-007396?style=flat-square&logo=openjdk&logoColor=white) ![Spring Boot](https://img.shields.io/badge/Spring%20Boot-6DB33F?style=flat-square&logo=springboot&logoColor=white) |
| **Frontend (Mobile)** | ![Flutter](https://img.shields.io/badge/Flutter-02569B?style=flat-square&logo=flutter&logoColor=white) ![Dart](https://img.shields.io/badge/Dart-0175C2?style=flat-square&logo=dart&logoColor=white) |
| **Database** | ![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=flat-square&logo=postgresql&logoColor=white) |

<br/>

## 📌 작업 진행 상황 (Roadmap)

- [x] 프로젝트 기획 및 요구사항 정의
- [x] 전체 아키텍처 설계 ([docs/](./docs))
- [x] 데이터베이스 설계 (PostgreSQL)
- [ ] 백엔드 API 개발 (Spring Boot)
- [ ] 앱 UI/UX 설계 및 구현 (Flutter)
- [ ] 하루 기록 기능
- [ ] 감정 분석 및 테마(배경·필체) 적용
- [ ] 감정 기반 음악 설정
- [ ] 하루 공유 기능

> 진행 과정 및 상세 내용은 추후 계속 추가될 예정입니다.

<br/>

## 📂 프로젝트 구조

`record`는 **모노레포**로, 하나의 저장소에서 모바일 앱과 백엔드를 함께 관리합니다.

```
record/
├─ app/        # Flutter 모바일 앱 (Dart)
├─ backend/    # Spring Boot 백엔드 (Java, MyBatis)
└─ docs/       # 설계 문서
```

> 현재는 설계 단계로, 모노레포 디렉터리 이전 및 백엔드 스캐폴딩은 후속 작업으로 진행됩니다.

### 📑 설계 문서

| 문서 | 내용 |
| --- | --- |
| [docs/architecture.md](./docs/architecture.md) | 전체 아키텍처 개요, 핵심 결정사항, 트레이드오프 |
| [docs/database.md](./docs/database.md) | PostgreSQL ERD 및 전체 DDL, 인덱스 전략 |
| [docs/backend.md](./docs/backend.md) | Spring Boot + MyBatis 구조, JWT 인증, LLM 연동 |
| [docs/mobile.md](./docs/mobile.md) | Flutter Feature-first 구조, Riverpod, 테마 적용 |
| [docs/api-contract.md](./docs/api-contract.md) | REST API 계약 (`/api/v1`) |

<br/>

<!-- TODO: API 명세 상세, 스크린샷 등 추후 추가 예정 -->
