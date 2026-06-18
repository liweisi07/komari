#!/usr/bin/env bash

# 定义文件路径
CRON_ENV_FILE="/app/cron_env.sh"
CRONTAB_FILE="/etc/crontabs/root"
BACKUP_SCRIPT="/app/komari_bak.sh"
SUB_LINK_SCRIPT="/app/sub_link.sh"
CADDYFILE="/app/Caddyfile"
SUPERVISOR_CONF="/etc/supervisor/conf.d/komari.conf"

# 设置备份相关的环境变量默认值
BACKUP_TIME=${BACKUP_TIME:-"0 20 * * *"}
BACKUP_DAYS=${BACKUP_DAYS:-"10"}

# 配置变量
CADDY_PROXY_PORT=${CADDY_PROXY_PORT:-'8443'}
KOMARI_PORT=${KOMARI_PORT:-'25774'}

echo "#!/usr/bin/env bash" > "$CRON_ENV_FILE"
echo "export GH_BACKUP_USER=\"$GH_BACKUP_USER\"" >> "$CRON_ENV_FILE"
echo "export GH_REPO=\"$GH_REPO\"" >> "$CRON_ENV_FILE"
echo "export GH_PAT=\"$GH_PAT\"" >> "$CRON_ENV_FILE"
echo "export GH_EMAIL=\"$GH_EMAIL\"" >> "$CRON_ENV_FILE"
echo "export BACKUP_DAYS=\"$BACKUP_DAYS\"" >> "$CRON_ENV_FILE"
chmod +x "$CRON_ENV_FILE"

# 根据 BACKUP_TIME 环境变量配置备份任务（默认 UTC 20:00，北京时间 04:00）
echo "$BACKUP_TIME . $CRON_ENV_FILE && $BACKUP_SCRIPT bak" > "$CRONTAB_FILE"

# 如果设置了 UUID，配置 Caddy 反代和生成订阅链接
if [ -n "$UUID" ]; then
    echo "检测到 UUID，配置 Caddy 反代..."
    
    # 导出环境变量供 sub_link.sh 使用
    export UUID CADDY_PROXY_PORT ARGO_DOMAIN
    
    # 生成 Caddyfile
    cat > "$CADDYFILE" << EOF
:$CADDY_PROXY_PORT {
    # 订阅链接访问
    handle /$UUID {
        file_server {
            root /tmp
            browse
        }
        rewrite * /list.log
    }

    # VLESS 反代
    reverse_proxy /vls* {
        to localhost:8002
    }

    # VMESS 反代
    reverse_proxy /vms* {
        to localhost:8001
    }
    
    # 其他请求反代到 Komari
    reverse_proxy {
        to localhost:$KOMARI_PORT
    }
}
EOF
    
    echo "正在生成 VLESS 和 VMESS 订阅链接..."
    bash "$SUB_LINK_SCRIPT"
else
    echo "未设置 UUID，跳过 Caddy 反代配置"
fi

# 生成 supervisor 配置文件
cat > "$SUPERVISOR_CONF" << EOF
[supervisord]
nodaemon=true
logfile=/dev/null
pidfile=/run/supervisord.pid

[program:cron]
command=/usr/sbin/crond -f
autostart=true
autorestart=true
stderr_logfile=/dev/null
stdout_logfile=/dev/null

[program:komari]
command=/app/komari server
autostart=true
autorestart=true
stderr_logfile=/dev/null
stdout_logfile=/dev/null

EOF

# 如果配置了 Caddy，添加 Caddy 进程配置
if [ -f "$CADDYFILE" ]; then
    cat >> "$SUPERVISOR_CONF" << EOF
[program:caddy]
command=caddy run --config $CADDYFILE
autostart=true
autorestart=true
stderr_logfile=/dev/null
stdout_logfile=/dev/null

EOF
fi

# 启动 supervisor 进程守护
echo "正在启动 Supervisor 进程管理器..."
supervisord -c /etc/supervisor/supervisord.conf
