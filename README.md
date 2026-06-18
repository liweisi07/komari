# komari-backup
## 当前镜像版本 v1.2.3

## GitHub 备份所需变量

> 这些变量用于将 Komari 面板数据备份至私有 GitHub 仓库

- GH_BACKUP_USER=your_github_username（备份仓库所有者的 GitHub 用户名）
- GH_REPO=your_private_repo_name（备份数据的目标私有仓库名）
- GH_PAT=your_github_personal_access_token（GitHub 个人访问令牌，需要 repo 权限）
- GH_EMAIL=your_github_email@example.com（提交备份时使用的 Git 邮箱）

## 原镜像可选变量

- ADMIN_USERNAME=登录用户名
- ADMIN_PASSWORD=登录密码
- KOMARI_ENABLE_CLOUDFLARED=是否开启CF隧道，true/false，默认 false
- KOMARI_CLOUDFLARED_TOKEN=隧道token

## 反代和端口配置

- CADDY_PROXY_PORT=反向代理服务监听端口，默认为 `8443`（当设置了 UUID 且未设置 ARGO_DOMAIN 时需要暴露）
- KOMARI_PORT=Komari 内部服务端口，默认为 `25774`

## 进程管理

komari 使用 **Supervisor** 来管理后台进程，确保各服务持续运行：

- **cron**: 定时任务服务（用于备份）
- **komari**: 主应用面板
- **caddy**: 反代服务（仅在设置了 UUID 时启用）

所有进程由 Supervisor 统一管理，如果某个进程意外退出会自动重启。

## 备份相关环境变量

- BACKUP_TIME=定时备份的 Cron 表达式，默认为 `0 20 * * *`（UTC 20:00，北京时间 04:00）
- BACKUP_DAYS=保留备份文件的天数，默认为 `10`

### BACKUP_TIME 使用示例

- `0 20 * * *` - 每天 UTC 20:00（北京时间 04:00）
- `0 4 * * *` - 每天 UTC 04:00（北京时间 12:00）
- `0 */6 * * *` - 每 6 小时一次
- `0 0 * * 0` - 每周一 UTC 00:00

## 节点订阅相关环境变量（VLESS 和 VMESS）

- UUID=唯一标识符，用于生成 VLESS 和 VMESS 订阅链接（**必需**，为空时不生成）
- ARGO_DOMAIN=服务器实际域名（**可选**，未设置时自动使用服务器公网 IP）
- CF_IP=Cloudflare 等 CDN 的优选 IP，用于优化连接性能（默认为 `ip.sb`，无需修改）
- CADDY_PROXY_PORT=反向代理服务的公网端口，订阅链接会使用此端口（默认为 `8443`）
- SUB_NAME=订阅名称，默认为 `komari`
- OUTPUT_FILE=订阅文件输出路径，默认为 `/tmp/list.log`

## Docker 部署命令

```bash
docker run -d \
  --name komari \
  --restart unless-stopped \
  -p 25774:25774 \
  -v ./komari-data:/app/data \
  -e GH_BACKUP_USER="your_github_username" \
  -e GH_REPO="your_private_repo_name" \
  -e GH_PAT="your_github_personal_access_token" \
  -e GH_EMAIL="your_github_email@example.com" \
  -e ADMIN_USERNAME="yourusername" \
  -e ADMIN_PASSWORD="yourpassword" \
  # 【可选】自定义备份时间和保留天数
  # -e BACKUP_TIME="0 4 * * *" \
  # -e BACKUP_DAYS="15" \
  # 【可选】启用 VLESS 和 VMESS 节点订阅（会启动 Caddy 反代）
  # -e UUID="your-uuid-here" \
  # -e ARGO_DOMAIN="your-domain.com" \
  # -e CF_IP="your-cf-ip" \
  # 【如果启用了 UUID 且未设置 ARGO_DOMAIN，需要暴露 CADDY_PROXY_PORT 端口（与 CADDY_PROXY_PORT 值保持一致）】
  # -e CADDY_PROXY_PORT="8443" \
  # -p 8443:8443 \
  # 【可选】如果你需要启用 Cloudflare Tunnel，请取消注释并填写以下两行
  # -e KOMARI_ENABLE_CLOUDFLARED="true" \
  # -e KOMARI_CLOUDFLARED_TOKEN="eyJxxxxx" \
  --log-opt max-size=5m \
  --log-opt max-file=5 \
  ghcr.io/jyucoeng/komari:latest
```

或者使用仓库中的 `docker-copmose.yml` 来部署，命令：`docker compose up -d`

### 自定义 CADDY_PROXY_PORT 的示例

如果你想使用不同的反代端口（例如 9999 而不是默认的 8443），可以这样配置：

```bash
docker run -d \
  --name komari \
  --restart unless-stopped \
  -p 25774:25774 \
  -p 9999:9999 \                    # 暴露自定义的反代端口
  -v ./komari-data:/app/data \
  -e GH_BACKUP_USER="your_github_username" \
  -e GH_REPO="your_private_repo_name" \
  -e GH_PAT="your_github_personal_access_token" \
  -e GH_EMAIL="your_github_email@example.com" \
  -e ADMIN_USERNAME="yourusername" \
  -e ADMIN_PASSWORD="yourpassword" \
  -e UUID="your-uuid-here" \
  -e ARGO_DOMAIN="your-domain.com" \     # 如果设置了域名，下面不需要暴露反代端口
  # -e ARGO_DOMAIN="" \                   # 如果不设置域名（自动获取公网IP），则需要暴露反代端口
  -e CADDY_PROXY_PORT="9999" \           # 自定义为 9999
  -e CF_IP="your-cf-ip" \
  # -p 9999:9999 \                       # 取消注释来暴露自定义的反代端口
  --log-opt max-size=5m \
  --log-opt max-file=5 \
  ghcr.io/jyucoeng/komari:latest
```

**注意**：`-p` 中的端口映射必须与 `CADDY_PROXY_PORT` 的值保持一致（都是 9999）。默认值为 8443。

## 备份还原

### 备份

镜像已集成自动备份脚本，根据 `BACKUP_TIME` 环境变量定时将 Komari 面板的全部数据（`/app/data/` 目录）备份至**私有 GitHub 仓库**。备份包括面板配置、主题设置、服务器列表等所有数据。默认每天 UTC 20:00（北京时间 04:00）执行备份，并根据 `BACKUP_DAYS` 环境变量保留指定天数内的备份文件。

手动备份：`docker exec komari /app/komari_bak.sh bak`

### 还原

- 暂停容器：`docker stop komari`
- 确认还原脚本的位置：`docker exec -it komari ls -l /app/komari_bak.sh`
- 执行还原：`docker exec komari /app/komari_bak.sh res`
- 重启容器：`docker start komari`

## 节点订阅功能

当设置了 `UUID` 环境变量时，容器启动时会自动生成 VLESS 和 VMESS 订阅链接，并通过 Caddy 反代提供访问。

### 工作流程

```
容器启动 (entrypoint.sh)
    ↓
检查 UUID 环境变量
    ↓
UUID 为空? ──→ 【是】──→ 跳过 Caddy 配置，仅运行 Komari
    ↓
  【否】
    ↓
① 导出环境变量
   export UUID, CADDY_PROXY_PORT, ARGO_DOMAIN
    ↓
② 生成 Caddyfile
   - 监听 CADDY_PROXY_PORT
   - 配置反代规则:
     • /vls* → localhost:8002 (VLESS)
     • /vms* → localhost:8001 (VMESS)
     • /$UUID → /tmp/list.log (订阅文件)
     • 其他 → localhost:25774 (Komari)
    ↓
③ 调用 sub_link.sh 生成订阅链接
   - 检查 ARGO_DOMAIN
   - 未设置时自动获取公网 IP
   - 生成 VLESS URL 使用 CF_IP:CADDY_PROXY_PORT
   - 生成 VMESS JSON 使用 CF_IP:CADDY_PROXY_PORT
   - 合并输出到 /tmp/list.log
    ↓
④ 生成 Supervisor 配置
   - 添加 cron 进程
   - 添加 komari 进程
   - Caddyfile 存在时，添加 caddy 进程
    ↓
⑤ 启动 Supervisor 进程管理器
   - 管理所有进程的生命周期
   - 进程异常时自动重启

【关键】端口暴露决策:
- UUID=未设置 → 无需暴露任何端口（除了 25774）
- UUID=已设置 + ARGO_DOMAIN=已设置 → 无需暴露 CADDY_PROXY_PORT
- UUID=已设置 + ARGO_DOMAIN=未设置 → 需暴露 CADDY_PROXY_PORT（自动用公网 IP）
```

### 地址和端口详解

订阅链接中会使用三个关键信息：

**1. CF_IP（优选IP，默认 ip.sb）**
   - 客户端实际连接的 IP 地址
   - 通常是 Cloudflare 等 CDN 的优选节点 IP
   - 用于优化连接性能
   - 例如: `vless://UUID@1.2.3.4:8443?...`

**2. CADDY_PROXY_PORT（反向代理端口，默认 8443）**
   - 反向代理服务的实际监听端口
   - 只有在**未设置 ARGO_DOMAIN** 时需要从外部访问
   - 当未设置 ARGO_DOMAIN 时，客户端连接到 `CF_IP:CADDY_PROXY_PORT`
   - 当设置了 ARGO_DOMAIN 时，客户端连接到 `ARGO_DOMAIN:CADDY_PROXY_PORT`（内部或 DNS 解析）
   - 反向代理服务将请求转发到后端的 vless/vmess 服务

**3. ARGO_DOMAIN（实际域名/IP）**
   - 服务器的实际域名或公网 IP
   - 用于 SNI（Server Name Indication）
   - 用于 HTTP Host 头验证
   - 如果未设置，sub_link.sh 会自动获取服务器公网 IP
   - **设置了 ARGO_DOMAIN** 时，订阅链接使用该域名，无需暴露 CADDY_PROXY_PORT
   - **未设置 ARGO_DOMAIN** 时，订阅链接使用公网 IP，需暴露 CADDY_PROXY_PORT

### 连接流程

**情况 1：设置了 ARGO_DOMAIN**
```
客户端连接到 ARGO_DOMAIN:CADDY_PROXY_PORT（域名+反代端口）
         ↓
    TLS 握手（SNI: ARGO_DOMAIN）
         ↓
   Caddy 反代服务
         ↓
后端服务（localhost:8002 或 localhost:8001）
```

**情况 2：未设置 ARGO_DOMAIN（自动获取公网 IP）**
```
客户端连接到 CF_IP:CADDY_PROXY_PORT（公网IP+反代端口）
         ↓
    TLS 握手（SNI: 公网IP）
         ↓
   Caddy 反代服务
         ↓
后端服务（localhost:8002 或 localhost:8001）
```

### 默认行为

- **设置了 ARGO_DOMAIN**: 使用设置的域名
- **未设置 ARGO_DOMAIN**: 自动获取服务器公网 IP

这样即使不设置 ARGO_DOMAIN，也能自动生成可用的订阅链接。

### 访问订阅链接

当启用了 UUID 时，Caddy 会在 `CADDY_PROXY_PORT` 端口监听，可通过以下方式访问订阅：

```bash
# 方式1：如果设置了 ARGO_DOMAIN，使用域名访问
http://ARGO_DOMAIN:CADDY_PROXY_PORT/UUID
# 例如
http://example.com:8443/your-uuid

# 方式2：如果未设置 ARGO_DOMAIN，使用公网 IP 访问
http://CF_IP:CADDY_PROXY_PORT/UUID
# 例如
http://1.2.3.4:8443/your-uuid

# 方式3：查看生成的订阅文件
docker exec komari cat /tmp/list.log

# 方式4：手动生成
docker exec komari bash /app/sub_link.sh
```

### 支持的协议

- **VLESS**: 使用 WebSocket + TLS 加密，路由为 `/vls*`
- **VMESS**: 使用 WebSocket + TLS 加密，路由为 `/vms*`

订阅链接中的内容已经过 Base64 编码，可直接用于支持的客户端导入。

**注意**：
- `CADDY_PROXY_PORT` 只有在**启用了 UUID 且未设置 ARGO_DOMAIN** 时才需要暴露（如 `-p 8443:8443`）
- 如果设置了 ARGO_DOMAIN，订阅链接会直接使用该域名，无需暴露 CADDY_PROXY_PORT
- 如果不设置 UUID，容器不会启动 Caddy，无需暴露该端口
- VLESS 和 VMESS 后端服务需要在 `localhost:8002` 和 `localhost:8001` 运行
- CF_IP 和 CADDY_PROXY_PORT 会自动包含在生成的订阅链接中
- 如果不需要订阅功能，可以不设置 UUID，Caddy 不会启动

### 致谢

- 参考项目：https://github.com/jyucoeng/Docker-for-Nezha-Argo-server-v0.x
- 原始项目：https://github.com/yutian81/komari-backup
