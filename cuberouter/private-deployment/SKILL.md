---
name: cuberouter-private-deployment
description: "Deploy cuberouter AI gateway from an offline tarball: ≥1 shared data node (PostgreSQL+Redis), N stateless app nodes, 1 nginx LB edge."
---

# CubeRouter Private Deployment (Offline)

核心架构(本 skill 的骨架): **≥1 台存储节点(共享 PostgreSQL + Redis)+ N 台应用节点(无状态, 多实例)+ 1 台 LB 节点(nginx TLS 终结)**。
所有应用节点指向同一存储节点, 凭完全一致的 `SESSION_SECRET` 组成集群; 应用层无状态可横向扩容(见 Scale-out), 存储层是唯一有状态层。

Validated end-to-end 2026-08-31 on 4 KubeVirt VMs (10.66.2.207-210, Ubuntu 22.04.5)。矩阵填充样例与验证证据: `examples/deployment-record.md`。

## When to use
- Deploying cuberouter (AI API gateway, Go/Gin + React, new-api-based) from an offline tarball (target machines have no registry access).
- Upgrading (new tarball), scale-out (adding an app node), or troubleshooting an existing private deployment.

## Deployment matrix — 先填这张表

部署前把所有值填好; 本文所有命令与 `references/templates.md` 的占位符都引用此表。

| 参数 | 含义 | 示例值(已验证实例) |
|---|---|---|
| `TARBALL` | 离线包路径(运维机上) | /home/ubuntu/cuberouter-v1.0.0.tar.gz |
| `IMAGE_TAG` | 镜像版本 tag | v1.0.0 |
| `DATA_IP` | 存储节点 IP | 10.66.2.207 |
| `APP_IPS` | 应用节点 IP 列表 (≥1, 建议 ≥2) | 10.66.2.208, 10.66.2.209 |
| `EDGE_IP` | LB 节点 IP (证书 SAN) | 10.66.2.210 |
| `EDGE_DOMAIN` | (可选) 入口域名, 替换 nginx `server_name` | — |
| `SUBNET` | 内网网段 (TRUSTED_PROXIES) | 10.66.2.0/24 |
| `OS_USER` | 各节点 SSH 用户 | ubuntu |
| `INSTALL_DIR` | 各节点部署目录 | /opt/cuberouter |

## Package anatomy (随 IMAGE_TAG 变化)
tarball → `docker-compose.yml` (app+redis+postgres single-node 参考), `docker-compose.docs.yml` (docs-user :4080 + docs-admin :4081, same image twice), `scripts/gen-tls-cert.sh` (private CA + server cert; SANs mandatory; mode B = generate new root CA; mode A = sign with provided CA cert+key), `images.tar` (~840MB, 5 prebuilt OCI images from internal harbor — offline `docker load`).
Images: suanova/cuberouter:{IMAGE_TAG}, library/postgres:15, library/redis:latest, suanova/cuberouter-docs-{user,admin}:{IMAGE_TAG}.
Template passwords are all `123456` — always replace.

## Reference topology (按角色)
- **data** ({DATA_IP}): postgres:15 + redis (requirepass + AOF); 5432/6379 仅对应用节点放行。
- **app ×N** ({APP_IPS}): 每节点 NODE_NAME 唯一; SESSION_SECRET 全部一致; SQL_DSN/REDIS_CONN_STRING → {DATA_IP}。
- **edge** ({EDGE_IP}): nginx 443 TLS 终结 (证书 SAN=EDGE_IP/EDGE_DOMAIN) → upstream 全部应用节点轮询; 80→301; docs compose。
- Do NOT co-locate LB and an app node (SPOF + tier anti-pattern).
所有 compose/nginx 模板: `references/templates.md` (参数化)。

## Procedure
1. Extract tarball locally; read compose + gen-tls-cert.sh before deploying.
2. Docker on each VM: `sudo apt-get install -y docker.io docker-compose-v2` (Ubuntu repo; 29.x on 22.04.5, current enough)。
   - [已验证环境备注] download.docker.com is usually blocked on CN private nets (SSL conn reset); the aliyun docker-ce mirror lacks Release metadata — unusable by apt.
   - dpkg lock on fresh VMs = unattended-upgrades. Find the REAL holder: `fuser /var/lib/dpkg/lock-frontend` and wait on that PID. Do NOT wait on `pgrep -x unattended-upgr` — the helper `unattended-upgrade-shutdown --wait-for-signal` matches that 15-char comm and runs forever (false "still installing").
3. TLS on operator host: `./scripts/gen-tls-cert.sh --ips <EDGE_IP> --out certs` (mode B)。Keep ca.crt — every client must trust it (system store or `curl --cacert`)。Renew with mode A (`--ca-cert/--ca-key`) to keep the same CA。
4. Secrets (operator host, chmod 600): PG/Redis pw = `openssl rand -hex 24` (hex = DSN-URL safe); SESSION_SECRET = `openssl rand -hex 32`, byte-identical on ALL app nodes. One .env per node.
5. Write per-role compose (references/templates.md, 填矩阵):
   - data: postgres user `cuberouter` (not root) + redis; healthchecks.
   - app: SQL_DSN/REDIS_CONN_STRING → <DATA_IP>; TRUSTED_PROXIES=<SUBNET>; NODE_NAME per node; plain HTTP :3000 (TLS belongs at edge).
   - edge: docs compose as-is + nginx conf (SSE: proxy_buffering off, 600s timeouts, HTTP/1.1 + Upgrade map).
6. Distribute: `mkdir -p <INSTALL_DIR> && chown <OS_USER>` on each VM; scp bundle; `sudo docker load -i images.tar` per VM (L2-fast, ~2min/VM).
7. Start order: data → app A → app B → edge. App "healthy" can take ~90s (healthcheck interval 30s).
   - CRITICAL: if the env file is not literally named `.env`, pass `--env-file <name>` on EVERY compose invocation (up/ps/restart/stop). A missed --env-file makes compose interpolate EMPTY secrets and the next `up` recreates containers with blank passwords.
8. Bootstrap ROOT admin — there are NO default credentials:
   - The first /api/user/register is a common user (role=1, hardcoded in Register()).
   - `POST /api/setup` {username ≤12 chars, password 8-20 with upper+lower+digit, confirmPassword} → creates root (role=100, quota 100M) and the Setup record. Only works while no Setup record AND no root user exist (check `GET /api/setup` first: {status, root_init, database_type}).
   - Login: POST /api/user/login → token at `data.access_token` (NOT data.token). Auth header: `Authorization: Bearer <access_token>`.
9. Verify:
   - /api/status 200 on each node direct + `curl --cacert ca.crt https://<EDGE_IP>/api/status` via LB.
   - Cross-node shared state (strict): create a token via /api/token/ on node A, then read the /api/token/ list DIRECTLY on node B. "Visible via LB" is ambiguous (round-robin may hit the write node).
   - LB distribution: count `GET /api/status` GIN lines in each node's `docker logs` (healthchecks add equal noise on both sides, so ~equal counts = balanced).
10. Harden (optional): ufw (templates.md 第 7 节), change root password in console, SESSION_COOKIE_SECURE=true + SESSION_COOKIE_TRUSTED_URL=https://<EDGE_IP 或 EDGE_DOMAIN> if Secure cookies are required (breaks direct-HTTP node sessions).

## API / product behavior notes (v1.0.0 实测, 随版本可能漂移)
- /api/option/ → 404 in this fork; do not use it for shared-state tests. Use /api/token/ (POST /, GET /, DELETE /:id).
- Token delete = GORM soft-delete (deleted_at; raw `count(*)` includes ghosts — check deleted_at). User delete = hard-cascade of that user's tokens.
- DeleteTokenById is owner-scoped: even root got "record not found" deleting another user's token.
- Register password policy: 8-20 chars, upper+lower+digit (API error messages are the spec).
- Startup banner prints "CubeRouter v0.0.0" — dev version string in the binary; the image tag is authoritative.
- "Refresh cookie is not secure" warning on plain-HTTP app nodes = expected (TLS at edge).
- Memory cache enabled, sync 60s — list reads can lag writes by up to ~60s.
- App auto-runs DB migrations (AutoMigrate) on start — upgrades need no manual migration step.

## Pitfalls (agent operations)
- Write-channel corruption: sequences like dollar+open-paren (and occasionally `data.get`) in scripts/files I generate sometimes arrive mangled on disk (`*(`, `=***`). After EVERY write_file/heredoc of an executable: `bash -n` / `python3 -m py_compile` + grep the critical lines before sending to a VM. Repair via python `chr(36)+'('` concatenation — never retype the literal sequence.
- Deeply nested inline `ssh '...'` one-liners get mangled by the same channel: put remote logic in a script file (scp + `bash script.sh`).
- python urllib: `Request(url, data=None)` defaults to GET — always pass method= explicitly. (A "DELETE" that returned the resource body was actually a GET.)
- Keep regex out of remote scripts (use literal grep/cut or a .py helper file) — regex metachar sequences are the most-corrupted class.
- Never ship template 123456 passwords; hex secrets avoid DSN escaping entirely.
- Per-step approval sessions: one terminal command = one logical step; approval prompts time out easily on fragmented steps. On timeout/denial: post a short status summary and wait.

## Upgrade (new tarball)
Extract → `docker load images.tar` (new tags) → update image refs in deploy-app.yml → on each app node `sudo docker compose --env-file <env> -f deploy-app.yml up -d` (volumes/env preserved; migrations run on start) → verify /api/status + logs. Data node untouched unless postgres/redis tags change (变化时先备份!).

## Scale-out (add app node)
Docker + image load on the new VM → deploy-app.yml + .env (copy SESSION_SECRET verbatim, new NODE_NAME) → up -d → add `server <new-ip>:3000` to the nginx upstream on edge → `nginx -t && systemctl reload nginx` → run the cross-node proof involving the new node.

## Reference
- `references/templates.md` — 参数化 compose/nginx/.env/验证模板 (填部署矩阵)。
- `examples/deployment-record.md` — 已验证实例记录 (10.66.2.207-210, 2026-08-31): 矩阵填充样例 + 验证证据。
