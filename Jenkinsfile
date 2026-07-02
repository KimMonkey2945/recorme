// =============================================================================
// recorme 백엔드 CI/CD 파이프라인 (Jenkins, 홈서버)
//
// 트리거: pollSCM 5분(웹훅 미사용 — 서버를 외부에 열지 않는 Tailscale 구성이라 GitHub 웹훅이
//         서버로 들어올 수 없으므로 폴링을 쓴다). push 하면 5분 내 자동 빌드·배포.
//
// 설계 포인트:
//  1) 빌드는 self-contained Dockerfile(backend/Dockerfile) "안"에서 일어난다.
//     → Jenkins 에 JDK/JAVA_HOME 이 없어도 되고, 과거 "JAVA_HOME 누락으로 조용히 실패"한
//       유형의 사고가 구조적으로 불가능하다(빌드 JDK 는 이미지 build 스테이지에 내장).
//  2) Jenkins 컨테이너는 호스트 docker 소켓으로 `docker build` / `docker compose` 를 실행한다.
//     (jenkins 이미지에 docker CLI 필요 — docs/deployment.md 의 커스텀 이미지 안내 참고.)
//
// 사전 준비(Jenkins UI, task 6):
//  - GitHub 저장소 자격증명(PAT 또는 deploy key) 등록.
//  - 이 Jenkinsfile 을 사용하는 Pipeline 잡 생성(SCM: recorme, Script Path: Jenkinsfile).
//  - 시크릿 .env 는 compose 가 jenkins 컨테이너에 /deploy-env/.env 로 마운트·주입한다(DEPLOY_ENV).
//    서버 deploy 디렉터리 경로는 compose 기동 시 DEPLOY_DIR 로 지정(docs/deployment.md Phase 6).
// =============================================================================

pipeline {
  agent any

  triggers {
    pollSCM('H/5 * * * *')   // 5분마다 git 변경 감지
  }

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  environment {
    IMAGE       = 'recorme-backend:latest'
    COMPOSE     = 'deploy/docker-compose.yml'
    // 시크릿 .env 경로(컨테이너 내부). compose 의 jenkins 서비스가 DEPLOY_ENV=/deploy-env/.env 로
    // 주입하고 서버 deploy 디렉터리를 /deploy-env 에 마운트한다. 없으면 기본값 사용.
    DEPLOY_ENV  = "${env.DEPLOY_ENV ?: '/deploy-env/.env'}"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Build image') {
      steps {
        // 컨텍스트 = backend/ (Dockerfile 이 내부에서 gradlew bootJar 수행, 통합테스트는 -x test)
        sh 'docker build -t $IMAGE ./backend'
      }
    }

    stage('Deploy') {
      steps {
        // 이미 빌드된 이미지로 backend 컨테이너만 무중단 재생성(--no-deps: db/jenkins 는 건드리지 않음).
        sh 'docker compose -f $COMPOSE --env-file $DEPLOY_ENV up -d --no-deps --no-build backend'
        sh 'docker image prune -f'
      }
    }
  }

  post {
    success {
      echo '배포 성공 — backend 컨테이너가 최신 이미지로 갱신됨.'
    }
    failure {
      // 조용한 실패 방지: 실패를 명시적으로 남긴다(로그·알림 연동은 추후).
      echo '❌ 배포 실패 — 위 로그에서 docker build/compose 단계 확인.'
    }
  }
}
