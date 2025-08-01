# GoReplay 트래픽 미러링을 위한 Makefile

# 포트 입력 확인 함수
check_port = $(if $(PORT),,$(error PORT 환경변수가 설정되지 않았습니다. 예: make start PORT=8080))

.PHONY: help
help:
	@echo "GoReplay 트래픽 캡처 도구"
	@echo ""
	@echo "사용 가능한 명령어:"
	@echo "  make start PORT=8080  - 트래픽 미러링 시작"
	@echo "  make stop             - 트래픽 미러링 중지"
	@echo "  make status           - 현재 실행 상태 확인"
	@echo "  make clean            - 로그 파일 삭제"
	@echo ""
	@echo "예시:"
	@echo "  make start PORT=8080"

.PHONY: start
start:
	$(call check_port)
	@chmod +x ./mirror-traffic.sh
	@PORT=$(PORT) ./mirror-traffic.sh start

.PHONY: stop
stop:
	@chmod +x ./mirror-traffic.sh
	@./mirror-traffic.sh stop

.PHONY: status
status:
	@chmod +x ./mirror-traffic.sh
	@./mirror-traffic.sh status

.PHONY: clean
clean:
	@echo "기존 로그 파일들을 삭제합니다..."
	@if [ -d "logs" ]; then \
		rm -f logs/*.gor logs/*.gor.gz; \
		echo "✅ 로그 파일 삭제 완료"; \
	else \
		echo "로그 디렉토리가 없습니다."; \
	fi
