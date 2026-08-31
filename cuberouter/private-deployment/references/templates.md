# CubeRouter Deployment Templates

Validated 2026-08-31 (v1.0.0, 10.66.2.207-210). Adjust IPs/hostnames per deployment.
Secrets live in per-node .env files (chmod 600), generated on the operator host with the
openssl rand subcommand: PG/Redis pw = 24 hex chars (DSN-URL safe), SESSION_SECRET = 32 hex
chars, byte-identical on ALL app nodes.

## 1. Data node - deploy-data.yml

```yaml
# cuberouter 数据层 — 10.66.2.207 (lwvm1)
# 仅 postgres + redis; 密码从 .env 注入; 5432/6379 仅对 .208/.209 放行 (ufw)
version: '3.4'

services:
  postgres:
    image: harbor.isuanova.com/library/postgres:15
    container_name: postgres
    restart: always
    environment:
      POSTGRES_USER: cuberouter
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: cuberouter
      TZ: Asia/Shanghai
    volumes:
      - pg_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U cuberouter -d cuberouter"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - cbr-data

  redis:
    image: harbor.isuanova.com/library/redis:latest
    container_name: redis
    restart: always
    command: ["redis-server", "--requirepass", "${REDIS_PASSWORD}", "--appendonly", "yes"]
    volumes:
      - redis_data:/data
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD-SHELL", "redis-cli -a ${REDIS_PASSWORD} ping 2>/dev/null | grep -q PONG"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - cbr-data

volumes:
  pg_data:
  redis_data:

networks:
  cbr-data:
    driver: bridge
```

## 2. Data node - .env

```
POSTGRES_PASSWORD=***
REDIS_PASSWORD=***
```

## 3. App node - deploy-app.yml (identical on every app node)

```yaml
# cuberouter 应用节点 — 10.66.2.208 / 10.66.2.209 (lwvm2 / lwvm3)
# 共享数据层在 .207; SESSION_SECRET 两节点必须一致 (从 .env 注入)
version: '3.4'

services:
  cuberouter:
    image: harbor.isuanova.com/suanova/cuberouter:v1.0.0
    container_name: cuberouter
    restart: always
    command: --log-dir /app/logs
    ports:
      - "3000:3000"
    volumes:
      - ./data:/data
      - ./logs:/app/logs
    environment:
      - SQL_DSN=${SQL_DSN}
      - REDIS_CONN_STRING=${REDIS_CONN_STRING}
      - SESSION_SECRET=***
      - NODE_NAME=${NODE_NAME}
      - TRUSTED_PROXIES=10.66.2.0/24
      - TZ=Asia/Shanghai
      - ERROR_LOG_ENABLED=true
      - BATCH_UPDATE_ENABLED=true
    healthcheck:
      test: ["CMD-SHELL", "wget -q -O - http://localhost:3000/api/status | grep -o '\"success\":\\s*true' || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
```

## 4. App node - .env (per node)

```
SQL_DSN=postgresql://cuberouter:<pgpw>@<data-ip>:5432/cuberouter
REDIS_CONN_STRING=redis://:<redis-pw>@<data-ip>:6379
SESSION_SECRET=<same 32-hex on all app nodes>
NODE_NAME=cuberouter-node-1   # node-2 on the second node
```

## 5. Edge node - nginx site (/etc/nginx/sites-available/cuberouter + symlink to sites-enabled; remove default)

```nginx
# nginx 接入层 — 10.66.2.210 (lwvm4)
# 443 TLS 终结 (SAN=10.66.2.210) → upstream 双应用节点; 80 跳 443
# 放在 /etc/nginx/sites-available/cuberouter, 软链到 sites-enabled
upstream cbr_backends {
    server 10.66.2.208:3000 max_fails=3 fail_timeout=10s;
    server 10.66.2.209:3000 max_fails=3 fail_timeout=10s;
}

map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    server_name 10.66.2.210;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name 10.66.2.210;
    ssl_certificate     /opt/cuberouter/certs/server.crt;
    ssl_certificate_key /opt/cuberouter/certs/server.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    # 仪表盘上传/大请求体
    client_max_body_size 200m;

    location / {
        proxy_pass http://cbr_backends;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        # WebSocket + LLM 流式 (SSE)
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_buffering off;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
        proxy_connect_timeout 10s;
    }
}
```

Edge start: sudo nginx -t && sudo systemctl reload nginx
Docs: sudo docker compose -f docker-compose.docs.yml up -d   (ports 4080 user / 4081 admin)

## 6. E2E verification pattern (python3, stdlib only - run on the edge node)

```python
# login: POST <node>/api/user/login with JSON username+password -> token at data.access_token
# create: POST <nodeA>/api/token/ with JSON name + empty models_limit, Bearer auth
# read:   GET <nodeB>/api/token/  (DIRECT on node B, not via LB) -> name visible
# delete: DELETE <lb>/api/token/<id>  (soft-delete; check deleted_at in DB)
# urllib: always pass method explicitly; data=None defaults to GET
```

## 7. ufw hardening appendix (VM-level; run per node after services are up)

```bash
# data node .207 - DB ports to app nodes only
sudo ufw allow from 10.66.2.208 to any port 5432 proto tcp
sudo ufw allow from 10.66.2.208 to any port 6379 proto tcp
sudo ufw allow from 10.66.2.209 to any port 5432 proto tcp
sudo ufw allow from 10.66.2.209 to any port 6379 proto tcp
sudo ufw allow 22
# app nodes .208/.209 - app port to edge only
sudo ufw allow from 10.66.2.210 to any port 3000 proto tcp
sudo ufw allow 22
# edge .210
sudo ufw allow 80
sudo ufw allow 443
sudo ufw allow 4080
sudo ufw allow 4081
sudo ufw allow 22
# enable on each node:
sudo ufw --force enable && sudo ufw status verbose
```
