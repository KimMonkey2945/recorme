// =============================================================================
// recorme 앱(Android APK) 빌드 파이프라인 (Jenkins, 홈서버)
//
// 트리거: 수동(버튼). Jenkins 에서 "파라미터와 함께 빌드" → API_BASE_URL 입력 후 빌드.
// 결과물: 서명된 app-release.apk 를 Jenkins 산출물(Artifacts)로 보관 → UI 에서 내려받아 폰에 설치.
//         (백엔드처럼 서버에 자동 반영되는 게 아니라, "APK 생성"까지가 앱 자동화의 끝이다.
//          폰 설치는 여전히 수동 — Jenkins 는 폰에 앱을 밀어넣지 못한다.)
//
// 빌드는 app/Dockerfile(Flutter SDK 내장 이미지) "안"에서 수행한다 → Jenkins/호스트에 Flutter·
// Android SDK 설치 불필요(백엔드와 같은 self-contained 철학, JDK/SDK 조용한 실패 차단).
//
// iOS 는 macOS 가 필요해 여기서 못 만든다 → iOS 는 Codemagic(codemagic.yaml) 사용.
//
// 사전 준비(1회, docs/deployment.md "Phase 6.5" 참고):
//  - 백엔드와 같은 Jenkins·docker 소켓을 쓰므로 별도 인프라는 없다. Pipeline 잡만 하나 더 만든다
//    (SCM: recorme, Script Path: Jenkinsfile.app).
//  - (권장) 릴리즈 서명: Jenkins → Manage Credentials 에 Secret file 2개 등록
//      · recorme-key-properties   ← 값 채운 app/android/key.properties
//      · recorme-release-keystore ← recorme-release.jks
//    key.properties 의 storeFile=recorme-release.jks 로 둘 것(빌드가 android/app/ 에 주입한다).
//  - 자격증명 미등록이면 RELEASE_SIGNING 을 꺼서 debug 서명으로 빌드(설치 테스트용, 덮어설치 업데이트 불가).
// =============================================================================

pipeline {
  agent any

  parameters {
    string(
      name: 'API_BASE_URL',
      defaultValue: '',
      description: '실기기가 붙을 서버 주소(포트까지, /api/v1 없이). 예: http://100.x.y.z:8080'
    )
    booleanParam(
      name: 'RELEASE_SIGNING',
      defaultValue: true,
      description: '릴리즈 키스토어로 서명(Credentials recorme-key-properties·recorme-release-keystore 필요). ' +
                   '끄면 debug 서명(테스트용 — 빌드마다 키가 달라 덮어설치 업데이트 불가).'
    )
  }

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  environment {
    IMAGE = 'recorme-app-builder:latest'
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Validate') {
      steps {
        script {
          if (!params.API_BASE_URL?.trim()) {
            error('API_BASE_URL 이 비었습니다. "파라미터와 함께 빌드"에서 서버 주소를 넣고 다시 실행하세요.')
          }
        }
      }
    }

    stage('Build APK') {
      steps {
        script {
          if (params.RELEASE_SIGNING) {
            // 릴리즈 서명: 서명 자료를 BuildKit secret 으로 주입(이미지 레이어에 안 남김).
            withCredentials([
              file(credentialsId: 'recorme-key-properties',   variable: 'KEYPROPS'),
              file(credentialsId: 'recorme-release-keystore', variable: 'KEYSTORE')
            ]) {
              sh '''
                DOCKER_BUILDKIT=1 docker build \
                  --target build \
                  --build-arg API_BASE_URL="$API_BASE_URL" \
                  --secret id=keyprops,src="$KEYPROPS" \
                  --secret id=keystore,src="$KEYSTORE" \
                  -t "$IMAGE" ./app
              '''
            }
          } else {
            // debug 서명 폴백: secret 미주입 → key.properties 부재 → build.gradle.kts 가 debug 키로 서명.
            sh '''
              DOCKER_BUILDKIT=1 docker build \
                --target build \
                --build-arg API_BASE_URL="$API_BASE_URL" \
                -t "$IMAGE" ./app
            '''
          }
        }
      }
    }

    stage('Extract APK') {
      steps {
        // build stage 이미지에서 APK 를 cp 로 추출(buildx --output 불필요 — docker cp 로 호환성 확보).
        // scratch 실행은 불가하지만 create(미실행)+cp 는 정상 동작한다.
        sh '''
          cid=$(docker create "$IMAGE")
          mkdir -p artifact
          docker cp "$cid":/workspace/build/app/outputs/flutter-apk/app-release.apk artifact/app-release.apk
          docker rm "$cid"
        '''
      }
    }
  }

  post {
    success {
      archiveArtifacts artifacts: 'artifact/app-release.apk', fingerprint: true
      echo '✅ APK 빌드 성공 — 이 빌드의 Artifacts 에서 app-release.apk 를 내려받아 폰에 설치하세요.'
    }
    failure {
      echo '❌ APK 빌드 실패 — 위 로그에서 flutter build / docker 단계를 확인하세요.'
    }
    always {
      // 이전 빌드의 dangling 이미지 정리(캐시 마운트는 유지되어 재빌드는 여전히 빠름).
      sh 'docker image prune -f || true'
    }
  }
}
