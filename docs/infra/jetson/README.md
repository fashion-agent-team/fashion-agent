# 젯슨 배포 (jetson-deploy)

맥북에서 `bootRun`으로 돌리던 서버 8개 + PostgreSQL + Redis를 팀 젯슨에 Docker Compose로 옮긴 설정입니다. 처음엔 젯슨 한 대(team4)에 다 올렸는데 8GB에 다 들어가지 않아서, 2026-11-13부터 **젯슨 오린 나노 8GB 두 대**로 나눠 돌립니다(2026-11-21 기준).

| 기기 | compose | 올라간 것 |
|---|---|---|
| 앱 서버 젯슨 (team4) | `docker-compose.yml` | nginx, gateway, edge-tts, agent, mcp-schedule, mcp-closet, so400m-embed, postgres, redis |
| 모델 서버 젯슨 (fashion-agent) | `node/docker-compose.yml` | mcp-clothes-state, mcp-face-check, mcp-weather, 모델 학습 |

두 젯슨은 Tailscale 사설망으로 이어집니다. agent는 MCP 서버를 주소로만 불러서, 옮길 때 앱 서버 `.env`의 `MCP_*_URL`만 바꿨습니다.
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
앱 서버 젯슨 Docker Compose (네트워크 fashion)
  nginx:80 ─ gateway:8080 ─┬ edge-tts:8099
                            ├ agent:8081 ─┬ mcp-schedule:8092  mcp-closet:8095   (같은 젯슨)
                            │             └ Tailscale ─▶ 모델 서버 젯슨
                            │                  mcp-weather:8091  mcp-clothes-state:8093  mcp-face-check:8094
                            │                  mcp-clothes-state ─ Tailscale ─▶ 앱 서버 so400m-embed:8096 (애매한 옷 종류만)
                            ├ /api/v1/schedules/** → mcp-schedule
                            └ postgres:5432 (pgvector pg17), redis:6379
```

- 밖에서 들어오는 문은 **gateway 하나**입니다. 같은 젯슨의 MCP 서버는 컨테이너 이름(`http://mcp-closet:8095/mcp` 등)으로, 모델 서버 젯슨의 MCP 서버와 so400m-embed는 Tailscale IP에만 연 포트로 부릅니다. 인증은 gateway가 합니다.
- 서버 이미지는 젯슨에서 각 레포의 Dockerfile로 직접 빌드합니다(arm64). ghcr 이미지는 쓰지 않습니다.
- 맥북 PostgreSQL의 `fashion` DB(account·closet·helper·schedule 스키마)를 `pg_dump`로 옮겼습니다.

## 폴더 구성

| 파일 | 하는 일 |
|---|---|
| `docker-compose.yml` | 앱 서버 젯슨. 서비스 9개(+선택 cloudflared). weather·clothes-state·face-check는 `--profile local-heavy`일 때만 여기서 뜸 |
| `node/docker-compose.yml` | 모델 서버 젯슨. mcp-clothes-state, mcp-face-check, mcp-weather. 포트는 `TS_IP`(Tailscale IP)에만 엶 |
| `nginx/default.conf` | gateway로 프록시. 업로드 20MB, 타임아웃 300초(GPT), WebSocket/SSE |
| `postgres/init.sql` | 새 DB일 때 vector 확장과 스키마 4개 생성 |
| `.env.example` | 키 **이름**만. 실제 `.env`는 커밋 금지(권한 600) |
| `scripts/make-env.sh` | `.env` 만들기. DB 비밀번호·JWT는 새로 만들고, API 키는 화면에 안 보이게 붙여 넣기 |
| `scripts/sync.sh` | 맥북 → 젯슨으로 레포 7개(`origin/develop`을 `git archive`), 이 폴더, FashionSigLIP 모델 보내기 |
| `scripts/db-migrate.sh` | 맥북 `fashion` DB → 젯슨 postgres 컨테이너로 복원 |
| `scripts/up.sh` | 젯슨에서 이미지 하나씩 빌드 후 실행 (`./scripts/up.sh mcp-closet`처럼 하나만도 됨) |
| `scripts/funnel.sh` | Tailscale Funnel 켜기/끄기 (`off`) |
| `scripts/tunnel-token.sh` | (선택) Cloudflare Tunnel 토큰 넣기 |

젯슨에서는 아래처럼 레포들과 나란히 둡니다. compose의 `build:`가 `../<레포>`를 가리킵니다.

```
~/fashion-servers/
  fashion-agent-gateway/  fashion-agent-agent/  mcp-weather/  mcp-schedule/
  mcp-clothes-state/  mcp-face-check/  mcp-closet/
  so400m-embed/    ← mcp-clothes-state/so400m-embed 내용
  jetson-deploy/   ← 이 폴더 (docs/infra/jetson 내용)
  models/so400m/open_clip_model.safetensors
```

모델 서버 젯슨:

```
~/fashion-servers/
  mcp-clothes-state/  mcp-face-check/  mcp-weather/
  fashion-agent-node/   ← node/ 폴더 내용 + .env
  models/marqo-fashionSigLIP-vision.onnx  models/fsiglip_lora_pattern8.onnx
```

두 젯슨 `.env`에서 서로를 가리키는 값(키 이름만):

| 젯슨 | 이름 | 값 |
|---|---|---|
| 앱 서버 | `MCP_WEATHER_URL`, `MCP_CLOTHES_STATE_URL`, `MCP_FACE_CHECK_URL` | `http://<모델 서버 Tailscale IP>:8091/mcp` 등 |
| 앱 서버 | `APP_TS_IP` | 앱 서버 자신의 Tailscale IP (so400m-embed 포트를 여기에만 엶) |
| 모델 서버 | `TS_IP` | 모델 서버 자신의 Tailscale IP |
| 모델 서버 | `CLOTHES_SO400M_URL` | `http://<앱 서버 Tailscale IP>:8096` (비우면 so400m 보조 꺼짐) |

## 메모리 (2026-11-21 배포 값)

앱 서버 젯슨 (다른 팀원 작업과 같이 씀):

| 서비스 | mem_limit | -Xmx | 비고 |
|---|---|---|---|
| gateway | 320m | 128m | `dev` 프로필(개발용 로그인 켬) |
| edge-tts | 96m | - | 엣지 목소리(선희·인준·현수) 사이드카, 파이썬 |
| agent | 448m | 176m | `mcp,openai,redis` 프로필, 세션은 Redis |
| mcp-schedule | 384m | 112m | |
| mcp-closet | 1408m | 160m | e5-small + FashionSigLIP 글 모델(int8, imageQuery) |
| so400m-embed | 2560m | - | GPU(fp16), 스왑 금지. 가중치 약 827MB |
| postgres | 128m | – | shared_buffers 32MB, 서비스마다 Hikari 풀 3개 |
| redis | 48m | – | maxmemory 32MB, 디스크 저장 안 함(사진 세션이 남지 않게) |
| nginx | 32m | – | |

모델 서버 젯슨 (모델 학습과 같이 씀, 서버마다 스왑 금지):

| 서비스 | mem_limit | -Xmx | 비고 |
|---|---|---|---|
| mcp-clothes-state | 2048m | 230m | YOLO26n들 + 색 CNN + FashionSigLIP vision + 무늬 LoRA(fp32 372MB) |
| mcp-face-check | 1024m | 320m | BiSeNet + 좌우 비교·눈화장·치아 모델 |
| mcp-weather | 320m | 112m | |

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
./scripts/up.sh              # 이미지 빌드(약 15분) + 실행
./scripts/funnel.sh          # 인터넷 공개
```

모델 서버 젯슨 (`node/docker-compose.yml`을 `~/fashion-servers/fashion-agent-node/`에 두고 `.env`를 채운 뒤):
```bash
cd ~/fashion-servers/fashion-agent-node
docker compose up -d --build
```
그다음 앱 서버 `.env`의 `MCP_*_URL`을 모델 서버 주소로 바꾸고 `docker compose up -d agent`로 agent만 다시 띄웁니다.
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
| 옷 확인만 안 됨 | 모델 서버 젯슨이 꺼졌거나 Tailscale이 끊김 | 모델 서버에서 `docker compose ps`, 앱 서버에서 `curl http://<모델 서버 Tailscale IP>:8093/actuator/health` |
