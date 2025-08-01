# GoReplay 트래픽 캡처 도구

이 도구는 GoReplay를 사용하여 HTTP 트래픽을 캡처하고 로깅하는 스크립트입니다.

## 주요 기능

- 지정된 포트의 HTTP 트래픽을 실시간으로 캡처
- 내부 IP 주소를 기반으로 한 파일명 자동 생성
- 정적 리소스(CSS, JS, 이미지 등) 자동 필터링
- **분 단위 자동 로테이션 및 gzip 압축**
- 7일 이후 압축 파일 자동 삭제

## 시스템 요구사항

- macOS 또는 Linux
- sudo 권한 (GoReplay는 raw socket을 사용하므로 관리자 권한 필요)
- curl, tar (GoReplay 설치용)
- gzip (로그 압축용)

## 설치 및 사용법

### 1. 트래픽 캡처 시작

```bash
make start PORT=8080
```

### 2. 상태 확인

```bash
make status
```

### 3. 트래픽 캡처 중지

```bash
make stop
```

### 4. 로그 파일 삭제

```bash
make clean
```

## 캡처되는 트래픽

### 포함되는 HTTP 메서드
- GET, POST, PUT, DELETE, PATCH

### 제외되는 파일 확장자
- 이미지: png, jpg, jpeg, gif, ico, svg
- 스타일시트: css
- 스크립트: js
- 폰트: woff, woff2, ttf, eot
- 문서: pdf, zip
- 비디오: mp4, avi, mov
- HTML: html, htm

## 로그 파일 구조

- **위치**: `./logs/` 디렉토리
- **파일명 형식**: `{내부IP}_requests_{YYYYMMDD}_{HHMM}.gor`
- **로테이션**: 분 단위 자동 로테이션
- **압축**: 1분 후 자동 gzip 압축
- **정리**: 7일 후 자동 삭제

### 예시 파일명
```
logs/192.168.0.41_requests_20250801_1705.gor      # 현재 기록 중
logs/192.168.0.41_requests_20250801_1704.gor.gz   # 압축된 파일
logs/192.168.0.41_requests_20250801_1703.gor.gz   # 압축된 파일
```

## GoReplay 설정

실행되는 명령어:

```bash
sudo gor \
    --input-raw :8080 \
    --output-file "logs/192.168.0.41_requests_%Y%m%d_%H%M.gor" \
    --output-file-flush-interval=5s \
    --output-file-append \
    --http-allow-method=GET \
    --http-allow-method=POST \
    --http-allow-method=PUT \
    --http-allow-method=DELETE \
    --http-allow-method=PATCH \
    --http-disallow-url '.*\.(css|js|png|jpe?g|gif|ico|svg|woff2?|ttf|eot|pdf|zip|mp4|avi|mov|html?|htm)(\?.*)?$'
```

## 로그 로테이션 및 압축

### 자동 프로세스
1. **실시간 로깅**: 현재 분 단위 파일에 트래픽 기록
2. **분 단위 로테이션**: 매분마다 새로운 파일 생성
3. **자동 압축**: 1분 지난 파일을 gzip으로 압축
4. **자동 정리**: 7일 지난 압축 파일 자동 삭제

### 파일 관리
- 현재 활성 파일: `.gor` 확장자
- 압축된 파일: `.gor.gz` 확장자
- 디스크 공간 절약을 위한 자동 압축

## 명령어 요약

```bash
make start PORT=8080     # 시작
make status             # 상태 확인
make stop               # 중지
make clean              # 로그 삭제
```

## 파일 구조

```
traffic-capture/
├── Makefile              # Make 명령어 정의
├── mirror-traffic.sh     # 주 실행 스크립트
├── README.md            # 사용 설명서
├── .gor.pid             # GoReplay 프로세스 ID
├── .gor.pid.rotate      # 로테이션 프로세스 ID
└── logs/                # 로그 파일 저장 디렉토리
    ├── *.gor           # 현재 기록 중인 로그
    └── *.gor.gz        # 압축된 로그 파일
```

## 트러블슈팅

### GoReplay 시작 실패
- sudo 권한 확인
- 포트 중복 사용 여부 확인: `lsof -i :포트번호`
- 네트워크 인터페이스 권한 확인

### 로그 파일이 생성되지 않음
- 대상 포트에 트래픽이 있는지 확인
- 디스크 공간 확인
- 권한 설정 확인

### 로테이션이 작동하지 않음
- 로테이션 프로세스 상태 확인: `make status`
- 시스템 시간 확인
- gzip 명령어 설치 확인

## 버전 정보
- GoReplay: v1.3.0 (자동 설치됨)
- 지원 플랫폼: macOS, Linux x64
