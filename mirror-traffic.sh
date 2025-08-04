#!/bin/bash

# PID 파일 경로
PID_FILE="./.gor.pid"

# GoReplay 설치 확인 및 설치 함수
install_goreplay() {
    if ! command -v gor &> /dev/null; then
        echo "GoReplay가 설치되어 있지 않습니다. 설치를 시작합니다..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            curl -L https://github.com/buger/goreplay/releases/download/1.3.3/gor_1.3.3_mac.tar.gz -o gor.tar.gz
            tar -xzf gor.tar.gz
            sudo mv gor /usr/local/bin/
            rm gor.tar.gz
            echo "GoReplay 설치 완료"
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            ARCH=$(uname -m)
            if [ "$ARCH" == "x86_64" ] || [ "$ARCH" == "amd64" ]; then
                curl -L https://github.com/buger/goreplay/releases/download/1.3.3/gor_1.3.3_x64.tar.gz -o gor.tar.gz
            else
                echo "지원하지 않는 리눅스 아키텍처입니다: $ARCH"
                exit 1
            fi
            tar -xzf gor.tar.gz
            sudo mv gor /usr/local/bin/
            rm gor.tar.gz
            echo "GoReplay 설치 완료"
        else
            echo "지원하지 않는 운영체제입니다."
            exit 1
        fi

        # GoReplay에 필요한 권한 설정
        setup_goreplay_permissions
    else
        echo "GoReplay가 이미 설치되어 있습니다."
        # 권한 확인
        check_goreplay_permissions
    fi
}

# GoReplay 권한 설정 함수
setup_goreplay_permissions() {
    echo "GoReplay 실행 권한을 설정합니다..."

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux에서 setcap 사용
        if command -v setcap &> /dev/null; then
            echo "setcap을 사용하여 네트워크 권한을 부여합니다..."
            sudo setcap cap_net_raw,cap_net_admin=eip /usr/local/bin/gor
            if [ $? -eq 0 ]; then
                echo "✅ GoReplay에 네트워크 권한이 부여되었습니다."
                echo "이제 sudo 없이 실행할 수 있습니다."
            else
                echo "⚠️  setcap 설정에 실패했습니다. sudo 권한이 필요할 수 있습니다."
            fi
        else
            echo "⚠️  setcap이 설치되어 있지 않습니다. sudo 권한이 필요합니다."
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS에서는 여전히 sudo가 필요할 수 있음
        echo "⚠️  macOS에서는 raw socket 접근을 위해 sudo 권한이 필요할 수 있습니다."
        echo "대안으로 --input-tcp 또는 파일 기반 입력을 고려해보세요."
    fi
}

# GoReplay 권한 확인 함수
check_goreplay_permissions() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux에서 setcap 권한 확인
        if command -v getcap &> /dev/null; then
            local caps=$(getcap /usr/local/bin/gor 2>/dev/null)
            if [[ "$caps" == *"cap_net_raw,cap_net_admin+eip"* ]]; then
                echo "✅ GoReplay에 필요한 네트워크 권한이 설정되어 있습니다."
                return 0
            else
                echo "⚠️  GoReplay 네트워크 권한이 설정되어 있지 않습니다."
                echo "권한 설정을 위해 다음 명령어를 실행하세요:"
                echo "sudo setcap cap_net_raw,cap_net_admin=eip /usr/local/bin/gor"
                return 1
            fi
        fi
    fi
    return 1
}

# 내부 IP 주소 가져오기 함수
get_internal_ip() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        INTERNAL_IP=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1)
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        INTERNAL_IP=$(hostname -I | awk '{print $1}')
    else
        INTERNAL_IP="unknown-ip"
    fi

    if [ -z "$INTERNAL_IP" ]; then
        INTERNAL_IP="unknown-ip"
    fi

    echo "내부 IP 주소: $INTERNAL_IP"
}

# PORT 환경변수 확인
check_port() {
    if [ -z "$PORT" ]; then
        echo "PORT 환경변수가 설정되지 않았습니다."
        echo "사용법: PORT=8080 $0 start"
        exit 1
    fi
    echo "미러링할 포트: $PORT"
}

# 로그 설정
setup_logs() {
    LOG_DIR="./logs"
    mkdir -p $LOG_DIR
    chmod 755 $LOG_DIR

    # 분 단위 로테이션을 위한 파일명 패턴
    LOG_FILE="logs/${INTERNAL_IP}_requests_%Y%m%d_%H%M.gor"

    echo "로그 파일 패턴: $LOG_FILE (분 단위 로테이션)"
}

# 프로세스 시작 함수
start_process() {
    echo "GoReplay 시작 중..."

    # 기존 프로세스 확인
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            echo "GoReplay가 이미 실행 중입니다 (PID: $PID)"
            echo "먼저 'make stop' 명령어로 종료한 후 다시 시작하세요."
            exit 1
        else
            echo "이전 PID 파일을 정리합니다."
            rm -f "$PID_FILE"
        fi
    fi

    install_goreplay
    check_port
    get_internal_ip
    setup_logs

    echo "트래픽 미러링을 시작합니다..."

    # GoReplay 실행 권한 확인
    local use_sudo=false
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux에서 setcap 권한 확인
        if ! check_goreplay_permissions; then
            echo "⚠️  sudo 권한이 필요합니다."
            use_sudo=true
            if ! sudo -n true 2>/dev/null; then
                sudo -v || { echo "sudo 권한을 얻을 수 없습니다."; exit 1; }
            fi
        else
            echo "✅ sudo 없이 실행 가능합니다."
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS에서는 대부분 sudo가 필요
        echo "⚠️  macOS에서는 raw socket 접근을 위해 sudo 권한이 필요합니다."
        use_sudo=true
        if ! sudo -n true 2>/dev/null; then
            sudo -v || { echo "sudo 권한을 얻을 수 없습니다."; exit 1; }
        fi
    fi

    # GoReplay 실행 - 분 단위 로테이션
    if [ "$use_sudo" = true ]; then
        echo "sudo를 사용하여 GoReplay를 실행합니다..."
        sudo gor \
            --input-raw :$PORT \
            --input-raw-protocol http \
            --output-file "$LOG_FILE" \
            --output-file-flush-interval=5s \
            --output-file-append \
            --http-allow-method=GET \
            --http-allow-method=POST \
            --http-allow-method=PUT \
            --http-allow-method=DELETE \
            --http-allow-method=PATCH \
            --http-disallow-url '.*\.(css|js|png|jpe?g|gif|ico|svg|woff2?|ttf|eot|pdf|zip|mp4|avi|mov|html?|htm)(\?.*)?$' \
            &
    else
        echo "일반 사용자 권한으로 GoReplay를 실행합니다..."
        gor \
            --input-raw :$PORT \
            --input-raw-protocol http \
            --output-file "$LOG_FILE" \
            --output-file-flush-interval=5s \
            --output-file-append \
            --http-allow-method=GET \
            --http-allow-method=POST \
            --http-allow-method=PUT \
            --http-allow-method=DELETE \
            --http-allow-method=PATCH \
            --http-disallow-url '.*\.(css|js|png|jpe?g|gif|ico|svg|woff2?|ttf|eot|pdf|zip|mp4|avi|mov|html?|htm)(\?.*)?$' \
            &
    fi

    local gor_pid=$!
    echo $gor_pid > "$PID_FILE"

    # 로그 로테이션 및 압축 스크립트 시작
    start_log_rotation &
    local rotation_pid=$!
    echo $rotation_pid > "${PID_FILE}.rotate"

    echo "GoReplay PID: $gor_pid"
    echo "로그 로테이션 PID: $rotation_pid"

    # 프로세스 시작 확인
    sleep 3
    if ps -p "$gor_pid" > /dev/null 2>&1; then
        echo "✅ GoReplay가 성공적으로 시작되었습니다 (PID: $gor_pid)"
        echo "📁 로그 파일: $LOG_FILE"
        echo "🔧 분 단위로 자동 로테이션 및 gzip 압축됩니다"
        echo ""
        echo "🔧 명령어:"
        echo "  make status - 상태 확인"
        echo "  make stop   - 중지"
    else
        echo "❌ GoReplay 시작에 실패했습니다."
        rm -f "$PID_FILE" "${PID_FILE}.rotate"
        kill $rotation_pid 2>/dev/null
        exit 1
    fi
}

# 로그 로테이션 함수
start_log_rotation() {
    while true; do
        sleep 60  # 1분 대기

        # OS별 1분 전 시간 계산
        local prev_minute
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            prev_minute=$(date -v-1M +"%Y%m%d_%H%M")
        else
            # Linux
            prev_minute=$(date -d '1 minute ago' +"%Y%m%d_%H%M")
        fi

        local log_pattern="logs/${INTERNAL_IP}_requests_${prev_minute}.gor"

        # 로테이션 로그 출력
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 로테이션 체크: $log_pattern"

        # 파일 존재 확인 및 압축
        if ls $log_pattern 2>/dev/null 1>/dev/null; then
            for file in $log_pattern; do
                if [ -f "$file" ] && [ -s "$file" ]; then
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 로그 파일 압축 중: $file"
                    gzip "$file"
                    if [ $? -eq 0 ]; then
                        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 압축 완료: ${file}.gz"
                    else
                        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 압축 실패: $file"
                    fi
                fi
            done
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 압축할 파일 없음: $log_pattern"
        fi

        # 7일 이전 압축 파일 삭제
        local deleted_count=$(find logs/ -name "*.gor.gz" -mtime +7 -delete -print 2>/dev/null | wc -l)
        if [ $deleted_count -gt 0 ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${deleted_count}개의 오래된 압축 파일을 삭제했습니다"
        fi
    done
}

# 프로세스 종료 함수
stop_process() {
    local main_stopped=false
    local rotation_stopped=false

    # GoReplay 메인 프로세스 종료
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            echo "GoReplay 프로세스(PID: $PID)를 종료합니다..."
            sudo kill $PID

            # 종료 대기
            local count=0
            while ps -p "$PID" > /dev/null 2>&1 && [ $count -lt 10 ]; do
                sleep 1
                count=$((count + 1))
            done

            if ps -p "$PID" > /dev/null 2>&1; then
                echo "강제 종료합니다..."
                sudo kill -9 $PID
                sleep 2
            fi
            main_stopped=true
        else
            echo "메인 프로세스(PID: $PID)가 이미 종료되었습니다."
        fi
        rm -f "$PID_FILE"
    else
        echo "GoReplay 메인 프로세스가 실행 중이지 않습니다."
    fi

    # 로그 로테이션 프로세스 종료
    if [ -f "${PID_FILE}.rotate" ]; then
        ROTATE_PID=$(cat "${PID_FILE}.rotate")
        if ps -p "$ROTATE_PID" > /dev/null 2>&1; then
            echo "로그 로테이션 프로세스(PID: $ROTATE_PID)를 종료합니다..."
            kill $ROTATE_PID

            # 종료 대기
            local count=0
            while ps -p "$ROTATE_PID" > /dev/null 2>&1 && [ $count -lt 5 ]; do
                sleep 1
                count=$((count + 1))
            done

            if ps -p "$ROTATE_PID" > /dev/null 2>&1; then
                kill -9 $ROTATE_PID
            fi
            rotation_stopped=true
        else
            echo "로테이션 프로세스(PID: $ROTATE_PID)가 이미 종료되었습니다."
        fi
        rm -f "${PID_FILE}.rotate"
    fi

    if [ "$main_stopped" = true ] || [ "$rotation_stopped" = true ]; then
        echo "✅ GoReplay가 성공적으로 종료되었습니다."
    fi
}

# 상태 확인 함수
status_process() {
    local main_running=false
    local rotation_running=false

    # GoReplay 메인 프로세스 상태 확인
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            echo "✅ GoReplay가 실행 중입니다 (PID: $PID)"
            main_running=true

            # 프로세스 정보 표시
            echo ""
            echo "GoReplay 프로세스 정보:"
            ps -p "$PID" -o pid,ppid,user,cmd
        else
            echo "❌ PID 파일은 있지만 GoReplay 프로세스가 실행 중이지 않습니다."
            rm -f "$PID_FILE"
        fi
    else
        echo "❌ GoReplay가 실행 중이지 않습니다."
    fi

    # 로그 로테이션 프로세스 상태 확인
    if [ -f "${PID_FILE}.rotate" ]; then
        ROTATE_PID=$(cat "${PID_FILE}.rotate")
        if ps -p "$ROTATE_PID" > /dev/null 2>&1; then
            echo "✅ 로그 로테이션이 실행 중입니다 (PID: $ROTATE_PID)"
            rotation_running=true

            echo ""
            echo "로테이션 프로세스 정보:"
            ps -p "$ROTATE_PID" -o pid,ppid,user,cmd
        else
            echo "❌ 로테이션 PID 파일은 있지만 프로세스가 실행 중이지 않습니다."
            rm -f "${PID_FILE}.rotate"
        fi
    else
        echo "❌ 로그 로테이션이 실행 중이지 않습니다."
    fi

    # 로그 파일 상태 확인
    echo ""
    echo "로그 파일 상태:"
    if [ -d "./logs" ]; then
        echo "최근 .gor 파일들:"
        ls -la logs/*.gor 2>/dev/null | tail -5 || echo "  .gor 파일이 없습니다."
        echo ""
        echo "압축된 .gor.gz 파일들:"
        ls -la logs/*.gor.gz 2>/dev/null | tail -5 || echo "  .gor.gz 파일이 없습니다."
    else
        echo "로그 디렉토리가 없습니다."
    fi

    if [ "$main_running" = true ] && [ "$rotation_running" = true ]; then
        return 0
    else
        return 1
    fi
}

# 메인 로직
case "$1" in
    start)
        start_process
        ;;
    stop)
        stop_process
        ;;
    status)
        status_process
        ;;
    restart)
        stop_process
        sleep 2
        start_process
        ;;
    *)
        echo "사용법: $0 {start|stop|status|restart}"
        echo "시작 예제: PORT=8080 $0 start"
        exit 1
        ;;
esac
