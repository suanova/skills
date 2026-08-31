# CubeRouter Deployment Templates (参数化)

用 `SKILL.md` 的部署矩阵填掉所有 `<占位符>`(如 `<DATA_IP>`, `<IMAGE_TAG>`)。`<APP_IP_1>`/`<APP_IP_2>`/... = 矩阵 `APP_IPS` 列表的每一项, 有几个应用节点写几行。
密钥在运维机生成, 存进各节点 `.env` (chmod 600):
PG/Redis 密码 = `openssl rand -hex 24` (hex = DSN-URL 安全), `SESSION_SECRET` = `openssl rand -hex 32`, 所有应用节点逐字节一致。

## 1. Data node — deploy-data.yml (部署在 <DATA_IP>)

```yaml
# cuberouter 数据层 — 仅 postgres + redis; 密码从 .env 注入; 5432/6379 仅对应用节点放行 (ufw, 见第 7 节)
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

## 2. Data node .env (chmod 600)

```
POSTGRES_PASSWORD=<openssl rand -hex 24 生成>
REDIS_PASSWORD=<openssl rand -hex 24 生成>
```

## 3. App node — deploy-app.yml (identical on every app node; 部署在 <APP_IP_N>)

```yaml
# cuberouter 应用节点 — 共享数据层 <DATA_IP>; SESSION_SECRET 所有节点一致 (从 .env 注入)
version: '3.4'

services:
  cuberouter:
    image: harbor.isuanova.com/suanova/cuberouter:<IMAGE_TAG>
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
      - SESSION_SECRET=${SESSION_SECRET}
      - NODE_NAME=${NODE_NAME}
      - TRUSTED_PROXIES=<SUBNET>
      - TZ=Asia/Shanghai
      - ERROR_LOG_ENABLED=true
      - BATCH_UPDATE_ENABLED=true
    healthcheck:
      test: ["CMD-SHELL", "wget -q -O - http://localhost:3000/api/status | grep -o '\"success\":\\s*true' || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
```

## 4. App node .env (per node; chmod 600)

```
SQL_DSN=postgresql://cuberouter:<PG_PASSWORD>@<DATA_IP>:5432/cuberouter
REDIS_CONN_STRING=redis://:<REDIS_PASSWORD>@<DATA_IP>:6379
SESSION_SECRET=<32-hex, 所有应用节点逐字节一致>
NODE_NAME=cuberouter-node-1   # 每个应用节点递增 (node-2, node-3, ...)
```

## 5. Edge node — nginx site (/etc/nginx/sites-available/cuberouter + symlink to sites-enabled; remove default)

```nginx
# nginx 接入层 — <EDGE_IP>: 443 TLS 终结 (证书 SAN=<EDGE_IP> 或 <EDGE_DOMAIN>) → upstream 全部应用节点; 80 跳 443
upstream cbr_backends {
    server <APP_IP_1>:3000 max_fails=3 fail_timeout=10s;   # 每个应用节点一行; 扩容后加一行
    server <APP_IP_2>:3000 max_fails=3 fail_timeout=10s;
}

map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    server_name <EDGE_IP 或 EDGE_DOMAIN>;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name <EDGE_IP 或 EDGE_DOMAIN>;
    ssl_certificate     <INSTALL_DIR>/certs/server.crt;
    ssl_certificate_key <INSTALL_DIR>/certs/server.key;
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

Edge start: `sudo nginx -t && sudo systemctl reload nginx`
Docs: `sudo docker compose -f docker-compose.docs.yml up -d` (ports 4080 user / 4081 admin)

## 6. E2E verification pattern (python3, stdlib only — run on the edge node)

```
# login: POST <node>/api/user/login with JSON username+password -> token at data.access_token
# create: POST <nodeA>/api/token/ with JSON name + empty models_limit, Bearer auth
# read:   GET <nodeB>/api/token/  (DIRECT on node B, not via LB) -> name visible
# delete: DELETE <lb>/api/token/<id>  (soft-delete; check deleted_at in DB)
# urllib: always pass method explicitly; data=None defaults to GET
```

## 7. ufw hardening appendix (VM-level; run per node after services are up)

```bash
# data node <DATA_IP> - DB ports to app nodes only (每个应用节点一行)
sudo ufw allow from <APP_IP_1> to any port 5432 proto tcp
sudo ufw allow from <APP_IP_1> to any port 6379 proto tcp
sudo ufw allow from <APP_IP_2> to any port 5432 proto tcp
sudo ufw allow from <APP_IP_2> to any port 6379 proto tcp
sudo ufw allow 22
# app nodes <APP_IP_N> - app port to edge only
sudo ufw allow from <EDGE_IP> to any port 3000 proto tcp
sudo ufw allow 22
# edge <EDGE_IP>
sudo ufw allow 80
sudo ufw allow 443
sudo ufw allow 4080
sudo ufw allow 4081
sudo ufw allow 22
# enable on each node:
sudo ufw --force enable && sudo ufw status verbose
```
