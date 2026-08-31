# 示例实例记录 (Example instance record)

> 本文件是一次真实离线私有化部署的完整记录 —— 2026-08-31, 4 台 KubeVirt VM
> (10.66.2.207-210, Ubuntu 22.04.5), cuberouter v1.0.0。
>
> 用途: 作为 `SKILL.md` 部署矩阵的**填充样例**与端到端验证证据。
> **不是通用流程** —— 新部署请从 `SKILL.md`(填部署矩阵)+ `references/templates.md`(占位符)出发,
> 把本文件中的 IP/密码/路径替换为你的矩阵参数。

---

# CubeRouter v1.0.0 私有化部署与运维文档

- 部署日期: 2026-08-31
- 版本: v1.0.0 (harbor.isuanova.com/suanova/cuberouter:v1.0.0)
- 环境: KubeVirt 节点 10-66-2-1, 4 台 VM (各 8C/24G, Ubuntu 22.04.5, 30G RWX 数据盘)
- 部署包: /home/ubuntu/cuberouter-v1.0.0.tar.gz (离线, 含 5 个预构建镜像, 无需 registry)

## 1. 拓扑

| VM    | IP           | 角色   | 服务                                                        |
|-------|--------------|--------|-------------------------------------------------------------|
| lwvm1 | 10.66.2.207  | 数据层 | postgres:15 (库 cuberouter), redis (AOF 持久化)              |
| lwvm2 | 10.66.2.208  | 应用 A | cuberouter, NODE_NAME=cuberouter-node-1, :3000              |
| lwvm3 | 10.66.2.209  | 应用 B | cuberouter, NODE_NAME=cuberouter-node-2, :3000              |
| lwvm4 | 10.66.2.210  | 接入层 | nginx (443 TLS 终结, 80 跳 443), docs-user :4080, docs-admin :4081 |

要点:
- 两应用节点共享同一 PostgreSQL/Redis, SESSION_SECRET 完全一致 (多机无状态架构)
- nginx 做 443 TLS 终结 (证书 SAN=10.66.2.210, 本地 CA 签发), 双节点轮询, max_fails=3 fail_timeout=10s 自动摘除故障节点
- 支持 LLM 流式 (SSE): proxy_buffering off, 读写超时 600s

## 2. 访问信息

| 项             | 值                                                          |
|----------------|-------------------------------------------------------------|
| 主入口         | https://10.66.2.210  (80 自动 301 到 443)                    |
| 文档站(用户版) | http://10.66.2.210:4080                                     |
| 文档站(管理版) | http://10.66.2.210:4081                                     |
| 节点直连(调试) | http://10.66.2.208:3000 / http://10.66.2.209:3000           |
| 管理员账号     | root                                                        |
| 管理员密码     | Adm1ngSJMaswUVvd  (首次登录后请立即修改)                      |
| 密码另存于     | 本机 /tmp/admin_pw.txt, .210:/tmp/admin_pw.txt               |
| CA 证书        | /home/ubuntu/cbr-deploy/certs/ca.crt, .210:/opt/cuberouter/certs/ca.crt |
| 证书有效期     | 2026-08-31 ~ 2027-08-31 (365 天)                             |

客户端验证示例:

```
curl --cacert /home/ubuntu/cbr-deploy/certs/ca.crt https://10.66.2.210/api/status
```

浏览器使用: 将 ca.crt 导入操作系统/浏览器信任库后访问 https://10.66.2.210 无告警。

## 3. 各节点关键文件 (均在 VM 的 /opt/cuberouter/)

| 文件 | 位置 | 说明 |
|------|------|------|
| images.tar | 全部 4 台 | 镜像包 (~840MB), 部署完成后可删除 |
| docker-compose.yml / docker-compose.docs.yml | 全部 4 台 | 原包 compose (单节点参考) |
| deploy-data.yml + deploy-data.env | .207 | 数据层配置, .env 含 PG/Redis 强密码 |
| deploy-app.yml + deploy-app-node1.env / node2.env | .208 / .209 | 应用层配置, .env 含 DSN/SESSION_SECRET |
| certs/ (ca.crt server.crt server.key) | .210 | TLS 证书, server.key 权限 600 |
| nginx-cuberouter.conf | .210 | 已部署为 /etc/nginx/sites-available/cuberouter |
| step*.sh / *.py | .207-.210 | 本次部署/验证脚本, 留作参考 |

本机 /home/ubuntu/cbr-deploy/: 同上全部文件 + 本文档 + 原始部署包解包件。

## 4. 端口矩阵

| 节点        | 端口        | 用途              | 建议放通范围            |
|-------------|-------------|-------------------|-------------------------|
| .207        | 5432        | PostgreSQL        | 仅 .208/.209 (未做 ufw) |
| .207        | 6379        | Redis             | 仅 .208/.209 (未做 ufw) |
| .208/.209   | 3000        | 应用 HTTP         | 仅 .210 (未做 ufw)      |
| .210        | 80 / 443    | 入口 (301 / TLS)  | 办公网段                |
| .210        | 4080 / 4081 | 文档站            | 办公网段                |
| 全部        | 22          | SSH               | 运维机网段              |
## 5. 日常运维

状态总览 (在本机执行, 一次看 4 台):

```
for ip in 207 208 209 210; do
  echo "== 10.66.2.$ip =="
  ssh ubuntu@10.66.2.$ip 'sudo docker ps --format "table {{.Names}}\t{{.Status}}"'
done
```

启停 (在对应 VM 的 /opt/cuberouter/ 下):

```
# 数据层 .207
sudo docker compose --env-file deploy-data.env -f deploy-data.yml up -d
sudo docker compose --env-file deploy-data.env -f deploy-data.yml stop

# 应用层 .208 / .209 (env 文件名分别是 deploy-app-node1.env / deploy-app-node2.env)
sudo docker compose --env-file deploy-app-node1.env -f deploy-app.yml up -d

# 文档站 .210
sudo docker compose -f docker-compose.docs.yml up -d

# nginx .210
sudo nginx -t && sudo systemctl reload nginx
```

注意: env 文件不是 .env 这个名字时, 每次 compose 命令都必须带 --env-file,
否则会按空值插值, 下次 up 会用空密码重建容器。

日志:

```
sudo docker logs -f --tail 100 cuberouter     # 应用 (.208/.209)
sudo docker logs -f --tail 100 postgres       # 数据库 (.207)
sudo journalctl -u nginx -f                   # 接入层 (.210)
```

健康检查:

```
curl --cacert /home/ubuntu/cbr-deploy/certs/ca.crt https://10.66.2.210/api/status
sudo docker compose ps        # 各节点看 healthy 状态
```

进数据库 shell (.207):

```
sudo docker exec -it postgres psql -U cuberouter -d cuberouter
```

## 6. 备份与恢复

PostgreSQL (最重要, 在 .207):

```
mkdir -p /backup
sudo docker exec postgres pg_dump -U cuberouter cuberouter > /backup/cbr-daily.sql
```

恢复:

```
sudo docker exec -i postgres psql -U cuberouter -d cuberouter < /backup/cbr-daily.sql
```

每日自动备份 (crontab, 本机或 .207 上):

```
0 3 * * * cd /opt/cuberouter && sudo docker exec postgres pg_dump -U cuberouter cuberouter > /backup/cbr-daily.sql
```

多日留存: 备份文件名加日期 (手工替换或用 date 命令生成), 并配 find 清理过期文件。

Redis: 已开 AOF (appendonly yes), 数据在 redis_data 卷。内容主要是会话/缓存,
丢失可接受; 需要整体备份时打包 redis_data 卷即可。

配置文件备份 (含全部密码, 重要):

```
tar -czf /backup/cbr-config.tar.gz \
  /opt/cuberouter/deploy-*.yml /opt/cuberouter/deploy-*.env \
  /opt/cuberouter/certs /etc/nginx/sites-available/cuberouter
```
## 7. 版本升级

前提: 新版本离线包已在本机 (如 cuberouter-v1.1.0.tar.gz)。

```
1. 解包, 确认新镜像 tag (如 v1.1.0)
2. 每台应用节点: sudo docker load -i images.tar
3. 修改 deploy-app.yml 中 image 行为新 tag
4. 各应用节点滚动重启:
   sudo docker compose --env-file deploy-app-node1.env -f deploy-app.yml up -d
   (up -d 只重建变化的容器; 启动时自动执行数据库迁移, 无需手工迁移)
5. 验证: /api/status、登录、docker logs 看版本与迁移日志
6. 数据节点不动 (除非 postgres/redis tag 变化, 变化时先备份!)
7. 文档站: .210 上 load 新文档镜像 + 更新 docker-compose.docs.yml 的 image 后 up -d
```

回滚: 旧镜像 tag 未被删除前, 把 image 行改回旧 tag 再 up -d 即可
(若执行过 docker image prune, 需重新 load 旧 images.tar —— 所以旧包建议保留)。

## 8. 扩容 (加应用节点)

```
1. 新 VM: apt 装 docker.io + docker-compose-v2; scp images.tar 后 docker load
2. scp deploy-app.yml 到 /opt/cuberouter/; 新建 .env:
   - SESSION_SECRET 与 .208/.209 逐字节一致 (直接复制)
   - NODE_NAME=cuberouter-node-3 (新名字)
   - SQL_DSN / REDIS_CONN_STRING 指向 .207
3. up -d, 等 healthy (~90s 内)
4. .210: /etc/nginx/sites-available/cuberouter 的 upstream 加一行
   server <新IP>:3000 max_fails=3 fail_timeout=10s;
5. sudo nginx -t && sudo systemctl reload nginx
6. 验证: 新节点上创建测试 token -> 旧节点直连读到 -> 删除
```

## 9. 证书续期 (2027-08-31 前)

```
# 本机, 复用现有 CA (客户端无需重新导入):
cd /home/ubuntu/cbr-deploy
./scripts/gen-tls-cert.sh --ips 10.66.2.210 --ca-cert certs/ca.crt --ca-key certs/ca.key --out certs

# 分发到 .210:
scp certs/server.crt certs/server.key ubuntu@10.66.2.210:/opt/cuberouter/certs/

# .210 上生效:
sudo nginx -t && sudo systemctl reload nginx

# 验证:
curl --cacert certs/ca.crt https://10.66.2.210/api/status
```

## 10. 安全加固 (TODO, 尚未实施)

1. ufw 收紧 (在对应 VM 执行, 先确认业务不受影响再 enable):
   - .207: 5432/6379 仅来自 .208/.209
   - .208/.209: 3000 仅来自 .210
   - .210: 443/4080/4081/80 放行办公网段, 22 放行运维机
   - 精确命令见 skill references/templates.md 第 7 节
2. 修改 root 密码 (控制台 -> 个人资料)
3. 如需 Secure cookie: 应用节点加
   SESSION_COOKIE_SECURE=true 与 SESSION_COOKIE_TRUSTED_URL=https://10.66.2.210
   (副作用: 直连 http://节点:3000 的会话会失效, 仅走 LB 时才有意义)
4. 定期数据库备份 (见第 6 节 cron)
5. 运维机访问数据库不建议直接开端口, 用 SSH 隧道:
   ssh -L 15432:10.66.2.207:5432 ubuntu@10.66.2.207
   然后本机连 127.0.0.1:15432
## 11. 故障排查速查

| 现象 | 排查 |
|------|------|
| LB 502 | 两节点 :3000 是否都挂 (直连 curl); docker logs; 单节点挂时 nginx 10s 内自动摘除 |
| 登录 401 | 密码是否已改; token 是否过期; 看节点日志具体报错 |
| LB 只打单节点 | 正常: 故障节点被 max_fails 摘除; 看该节点 3000 与日志 |
| 应用连不上 DB | DSN/密码 (是否漏 --env-file); 5432 通不通; postgres 日志 |
| healthcheck 不健康 | 容器内 curl localhost:3000/api/status; env 是否为空 |
| 写入后立刻读不到 | 内存缓存同步周期 60s, 稍等再查 |
| 版本显示 v0.0.0 | 正常 (二进制内 dev 版本串), 以镜像 tag 为准 |
| token 删了 DB 还在 | GORM 软删除 (deleted_at), API 不可见, 正常 |
| 删他人 token 报 record not found | 删除接口有属主范围, 需 token 属主操作 |
| 注册报密码太弱 | 规则 8-20 位且含大写+小写+数字 |

## 12. 产品行为备忘 (v1.0.0 实测)

1. 无默认管理员: 首个注册用户是普通用户 (role=1); root 用 POST /api/setup 初始化
   (仅在初始化前可用: GET /api/setup 查 status/root_init; 用户名 <=12 位, 密码 8 位起)
2. 登录返回字段是 data.access_token (不是 token)
3. /api/option/ 在本版本返回 404 (fork 改动), 勿用
4. token 删除 = 软删除 (deleted_at); 用户删除 = 物理删除并级联删其 token
5. 内存缓存开启, 同步周期 60s
6. 应用启动自动执行数据库迁移 (AutoMigrate)

## 13. 已知限制

- .2 网段只有一个物理节点 (10-66-2-1): VM 无法热迁移; 物理节点故障 = 4 台全停
  (本部署是软件层高可用的生产模拟, 不是物理 HA)
- .210 (LB) 是入口单点: 该 VM 故障时流量入口丢失, 应用层本身可直连兜底
  (https 不可用, 可临时用 http://10.66.2.208:3000)
- 需要真正入口 HA 时: 第二台 edge + keepalived VIP, 或前置硬件负载均衡

## 附录: 本次部署的验证证据 (2026-08-31)

- 4 节点全部 healthy; LB 轮询双节点请求计数 43/42
- 跨节点共享状态: node-1 创建 token, node-2 直连读到, 经 LB 删除成功
- 根用户初始化: POST /api/setup -> root (role=100, 初始配额 1 亿)
- 数据库终态: 仅 root 一个用户, 无有效 token
