# 젯슨 배포 (jetson-deploy)

맥북에서 `bootRun`으로 돌리던 서버 8개 + PostgreSQL + Redis를 팀 젯슨(team4, Jetson Orin Nano 8GB)에 Docker Compose로 옮긴 설정입니다.
앱은 `https://simcheong.java21.net` 하나로 접속하고, 맥북이 꺼져 있어도, 와이파이·LTE 어디서든 됩니다.

## 전체 흐름

```
아이폰 앱 (GATEWAY_URL=https://simcheong.java21.net)
  │ https
  ▼
강사님 서버 java21.net ─ Nginx Proxy Manager (simcheong.java21.net, Let's Encrypt 인증서)
  │ https  업스트림: https://team4.<tailnet>.ts.net
  ▼
Tailscale Funnel (젯슨이 바깥으로 연결을 걸어 둠, 공유기 포트 안 엶)
  │ http://127.0.0.1:80
  ▼
젯슨 Docker Compose (네트워크 fashion)
  nginx:80 ─ gateway:8080 ─┬ agent:8081 ─ MCP 6개
                            │    mcp-weather:8091  mcp-schedule:8092  mcp-clothes-state:8093
                            │    mcp-face-check:8094  mcp-closet:8095  mcp-helper:8096
                            ├ /api/v1/schedules/** → mcp-schedule
                            ├ /api/v1/me/contacts, /h/** → mcp-helper (가족 답장 페이지)
                            └ postgres:5432 (pgvector pg17), redis:6379
```

- 밖에서 들어오는 문은 **gateway 하나**입니다. MCP 서버들은 밖에 열지 않고 컨테이너 이름(`http://mcp-weather:8091/mcp` 등)으로 서로 부릅니다. 인증은 gateway가 합니다.
- 서버 이미지는 젯슨에서 각 레포의 Dockerfile로 직접 빌드합니다(arm64). ghcr 이미지는 쓰지 않습니다.
- 맥북 PostgreSQL의 `fashion` DB(account·closet·helper·schedule 스키마)를 `pg_dump`로 옮겼습니다.

## 폴더 구성

| 파일 | 하는 일 |
|---|---|
| `docker-compose.yml` | 서비스 11개(+선택 cloudflared). 메모리 상한, JVM 옵션, 헬스체크, 서비스 사이 주소 |
| `nginx/default.conf` | gateway로 프록시. 업로드 20MB, 타임아웃 300초(GPT), WebSocket/SSE |
| `postgres/init.sql` | 새 DB일 때 vector 확장과 스키마 4개 생성 |
| `.env.example` | 키 **이름**만. 실제 `.env`는 커밋 금지(권한 600) |
| `scripts/make-env.sh` | `.env` 만들기. DB 비밀번호·JWT는 새로 만들고, API 키는 화면에 안 보이게 붙여 넣기 |
| `scripts/sync.sh` | 맥북 → 젯슨으로 레포 8개(`origin/develop`을 `git archive`), 이 폴더, FashionSigLIP 모델 보내기 |
| `scripts/db-migrate.sh` | 맥북 `fashion` DB → 젯슨 postgres 컨테이너로 복원 |
| `scripts/up.sh` | 젯슨에서 이미지 하나씩 빌드 후 실행 (`./scripts/up.sh mcp-closet`처럼 하나만도 됨) |
| `scripts/funnel.sh` | Tailscale Funnel 켜기/끄기 (`off`) |
| `scripts/tunnel-token.sh` | (선택) Cloudflare Tunnel 토큰 넣기 |

젯슨에서는 아래처럼 레포들과 나란히 둡니다. compose의 `build:`가 `../<레포>`를 가리킵니다.

```
~/fashion-servers/
  fashion-agent-gateway/  fashion-agent-agent/  mcp-weather/  mcp-schedule/
  mcp-clothes-state/  mcp-face-check/  mcp-closet/  mcp-helper/
  jetson-deploy/   ← 이 폴더 (docs/infra/jetson 내용)
  models/marqo-fashionSigLIP-vision.onnx
```

## 메모리 (젯슨 8GB를 다른 팀원 작업과 같이 씀)

| 서비스 | mem_limit | -Xmx | 비고 |
|---|---|---|---|
| gateway | 320m | 128m | `dev` 프로필(개발용 로그인 켬) |
| agent | 352m | 144m | `mcp,openai,redis` 프로필, 세션은 Redis |
| mcp-weather | 256m | 112m | |
| mcp-schedule | 288m | 112m | |
| mcp-clothes-state | 832m | 160m | YOLO 2개 + FashionSigLIP vision 354MB. `.env`에서 `CLOTHES_EMBED_MODEL=` 비우면 끔(512m로 줄여도 됨) |
| mcp-face-check | 512m | 256m | 힙 128m로는 모델 로딩 중 OOM이라 올림 |
| mcp-closet | 1200m | 128m | e5-small + FashionSigLIP 글 모델(int8, imageQuery). 실제 약 1.0GB |
| mcp-helper | 256m | 112m | |
| postgres | 128m | – | shared_buffers 32MB, 서비스마다 Hikari 풀 3개 |
| redis | 48m | – | maxmemory 32MB, 디스크 저장 안 함(사진 세션이 남지 않게) |
| nginx | 32m | – | |

JVM 공통: `-XX:+UseSerialGC -XX:TieredStopAtLevel=1 -XX:ReservedCodeCacheSize=32m -Xss512k -XX:+ExitOnOutOfMemoryError`.
상한을 넘으면 그 컨테이너만 죽고 `restart: unless-stopped`로 다시 뜹니다. `docker stats --no-stream`으로 보고 조정하세요.

## 처음 세팅 (한 번만)

젯슨 (sudo 필요):
```bash
sudo apt install -y docker-compose-v2
sudo usermod -aG docker $USER          # 다시 로그인
sudo tailscale set --operator=$USER    # funnel을 sudo 없이
```
젯슨이 속한 tailnet의 관리자가 Funnel을 허용해야 합니다(`funnel.sh`를 처음 실행하면 나오는 링크에서 Grant).

맥북:
```bash
cd ~/Documents/fashion-servers/jetson-deploy
./scripts/make-env.sh        # .env 만들기
./scripts/sync.sh            # 젯슨으로 보내기
```
젯슨:
```bash
cd ~/fashion-servers/jetson-deploy
docker compose up -d postgres
```
맥북:
```bash
./scripts/db-migrate.sh      # DB 옮기기
```
젯슨:
```bash
./scripts/up.sh              # 이미지 8개 빌드(약 15분) + 실행
./scripts/funnel.sh          # 인터넷 공개
```
Funnel 설정과 컨테이너(`restart: unless-stopped`)는 젯슨을 재부팅해도 자동으로 다시 켜집니다.

Nginx Proxy Manager(java21.net)의 사이트: 도메인 `simcheong.java21.net`, 업스트림 `https://team4.<tailnet>.ts.net`, Let's Encrypt, WebSocket 켬, 타임아웃 300초, **`client_max_body_size 20m`**.

## 자주 쓰는 명령 (젯슨)

| 할 일 | 명령 |
|---|---|
| 상태 | `docker compose ps`, `docker stats --no-stream` |
| 로그 | `docker compose logs -f agent` |
| 코드 바꾼 뒤 한 서비스만 다시 | 맥북 `./scripts/sync.sh` → 젯슨 `./scripts/up.sh mcp-closet` |
| 전부 멈춤 | `docker compose stop` |
| 바깥 확인 | `curl https://simcheong.java21.net/actuator/health` |

`sync.sh`는 **`origin/develop`**을 보냅니다. 내 브랜치를 올려 보려면 `DEPLOY_REF=origin/<브랜치> ./scripts/sync.sh`.

## 알아 둘 점

- **nginx 설정 파일을 바꾼 뒤에는 `docker compose up -d --force-recreate --no-deps nginx`.** 파일 하나를 bind mount해서, rsync로 덮어쓰면 `nginx -s reload`로는 새 파일이 안 보입니다.
- nginx는 `0.0.0.0:80`에 열려 있고 `allow`로 젯슨 자신·Docker·사설망·Tailscale만 받습니다. Funnel로 온 요청은 127.0.0.1을 거쳐 들어와서 통과합니다. `real_ip`(X-Forwarded-For)는 쓰지 않습니다. 쓰면 Funnel 요청이 바깥 IP로 바뀌어 403이 납니다.
- **gateway는 개발용 로그인(dev)이 켜진 채로 인터넷에 열려 있습니다.** 주소를 아는 사람은 누구나 들어와 GPT를 쓸 수 있고(사용자당 분당 30회 제한), 요금은 우리 OpenAI 키로 나갑니다. 발표·실사용 전에는 `GATEWAY_DEV_LOGIN=false` + 구글 로그인(Firebase)로 바꿔야 합니다.
- Funnel 구간 업로드가 느립니다(측정 약 50KB/s, 1MB 사진에 약 20초). 앱에서 사진을 보내기 전에 줄이면(긴 변 1280px, 품질 80 정도) 훨씬 빨라집니다.
- 젯슨은 다른 팀원 작업(VS Code 원격, 예전 과제 서비스)과 메모리를 같이 씁니다. 메모리가 모자라면 swap으로 느려지고, 심하면 리눅스가 가장 큰 프로세스를 강제로 끕니다.
- 선택: Cloudflare Tunnel(`--profile tunnel`, `CLOUDFLARE_TUNNEL_TOKEN`)도 compose에 준비돼 있습니다. java21.net DNS가 Cloudflare가 아니라서 지금은 쓰지 않습니다.

## 앱 빌드

```bash
flutter build ios --release --dart-define=GATEWAY_URL=https://simcheong.java21.net
flutter install --release            # 연결된 폰에 설치(앱 데이터가 초기화될 수 있음)
```

## 끄기

- 인터넷 공개만 끄기: 젯슨 `./scripts/funnel.sh off`
- 서버 전부 끄기: 젯슨 `docker compose down` (DB는 `pgdata` 볼륨에 남음, `-v`를 붙이면 DB까지 지워지니 주의)

## 문제 해결

| 증상 | 원인 | 해결 |
|---|---|---|
| `403 Forbidden` (nginx/1.27.x) | 젯슨 nginx `allow` 목록에 걸림 | `nginx/default.conf`의 allow 확인, real_ip를 켜지 않았는지 확인 후 nginx 재생성 |
| `413 Request Entity Too Large` (버전 없는 nginx) | Nginx Proxy Manager 업로드 제한(기본 1MB) | 프록시 매니저 사이트에 `client_max_body_size 20m;` |
| `502` / 응답 없음 | 프록시 매니저 → 젯슨 경로가 끊김 | 젯슨 `tailscale funnel status`, 업스트림 주소 확인. 강사님 서버는 젯슨 내부 IP로는 못 닿음 |
| 서비스가 계속 재시작 | 메모리 상한 초과(OOM) | `docker compose logs <서비스>`에서 `OutOfMemoryError` 확인 → 해당 `mem_limit`·`-Xmx` 올리기 |
| 전체가 느림 | 젯슨 메모리 부족 → swap | `free -h`, `docker stats`. 안 쓰는 프로세스 정리, SigLIP 끄기 |
