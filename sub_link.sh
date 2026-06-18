#!/usr/bin/env bash

#===============================================================
#          Komari Dashboard Subscription Link Generator
#
# 此脚本为 Komari 面板生成 VLESS 和 VMESS 节点订阅链接
# ---------------------------------------------------------------
# 功能:
#   - 生成 VLESS 节点链接
#   - 生成 VMESS 节点链接 (Base64 编码)
#   - 生成完整的订阅链接并保存到文件
#
# 工作流程：
#   1. 客户端 → CF_IP:443（Cloudflare CDN 优选 IP）
#   2. Cloudflare 隧道识别 SNI 和 Host 为 ARGO_DOMAIN
#   3. 隧道将流量转发到容器内 Caddy:8001
#   4. Caddy 反代到 Komari 面板 或 订阅文件
#
# 环境变量说明：
#   - ARGO_DOMAIN: Cloudflare 隧道配置的域名（必需）
#   - UUID: 订阅 UUID（必需）
#   - CF_IP: Cloudflare 等 CDN 的优选 IP，默认 ip.sb
#   - CADDY_PROXY_PORT: Caddy 反向代理的内部端口（用于内部通信）
#===============================================================

# 颜色定义
info() { echo -e "\033[32m\033[01m$*\033[0m"; }     # 绿色
error() { echo -e "\033[31m\033[01m$*\033[0m" && exit 1; } # 红色
hint() { echo -e "\033[33m\033[01m$*\033[0m"; }     # 黄色

# 获取国家代码
get_country_code() {
    local country_code="UN"
    local urls=("http://ipinfo.io/country" "https://ifconfig.co/country" "https://ipapi.co/country")
    
    for url in "${urls[@]}"; do
        if command -v curl &> /dev/null; then
            country_code=$(curl -s "$url" 2>/dev/null)
        else
            country_code=$(wget -qO- "$url" 2>/dev/null)
        fi
        
        if [ -n "$country_code" ] && [ ${#country_code} -eq 2 ]; then
            break
        fi
    done
    
    echo "$country_code"
}

# 获取服务器公网 IP
get_public_ip() {
    local ip=""
    local urls=("https://api.ipify.org" "https://ifconfig.co/ip" "https://ipapi.co/ip")
    
    for url in "${urls[@]}"; do
        if command -v curl &> /dev/null; then
            ip=$(curl -s "$url" 2>/dev/null)
        else
            ip=$(wget -qO- "$url" 2>/dev/null)
        fi
        
        if [ -n "$ip" ]; then
            break
        fi
    done
    
    echo "$ip"
}

# 主配置
UUID="${UUID:-}"
ARGO_DOMAIN="${ARGO_DOMAIN:-}"
CF_IP="${CF_IP:-ip.sb}"
SUB_NAME="${SUB_NAME:-komari}"
OUTPUT_FILE="${OUTPUT_FILE:-/tmp/list.log}"
# 注意：CADDY_PROXY_PORT 是容器内部端口，用于内部通信
# 从客户端视角，通过 ARGO_DOMAIN 访问时，隧道对外的端口是 443（HTTPS）
CADDY_PROXY_PORT="${CADDY_PROXY_PORT:-8001}"

# 检查必要的环境变量（UUID 是必需的）
if [ -z "$UUID" ]; then
    hint "UUID 未设置，跳过生成订阅链接"
    exit 0
fi

# ARGO_DOMAIN 在通过隧道时是必需的
if [ -z "$ARGO_DOMAIN" ]; then
    hint "ARGO_DOMAIN 未设置，跳过生成订阅链接"
    exit 0
fi

# 获取国家代码
COUNTRY_CODE=$(get_country_code)
info "检测到国家代码: $COUNTRY_CODE"

# 协议类型定义
XIEYI='vl'
XIEYI2='vm'

# 生成 VLESS 链接
# 说明：
#   - 连接到 CF_IP:443 是因为 Cloudflare 隧道对外暴露的是 HTTPS (443 端口)
#   - SNI 和 host 都设置为 ARGO_DOMAIN，用于隧道识别和 TLS 握手
VLESS_URL="vless://${UUID}@${CF_IP}:443?path=%2F${XIEYI}s%3Fed%3D2048&security=tls&encryption=none&host=${ARGO_DOMAIN}&type=ws&sni=${ARGO_DOMAIN}#${COUNTRY_CODE}-${SUB_NAME}-${XIEYI}"

# 生成 VMESS JSON
# 说明：
#   - add: CF_IP（CDN 优选 IP），这是客户端实际连接的地址
#   - port: 443（Cloudflare 隧道对外的 HTTPS 端口）
#   - host/sni: ARGO_DOMAIN（用于隧道识别和 TLS 握手）
VMESS_JSON="{ \"v\": \"2\", \"ps\": \"${COUNTRY_CODE}-${SUB_NAME}-${XIEYI2}\", \"add\": \"${CF_IP}\", \"port\": \"443\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"${ARGO_DOMAIN}\", \"path\": \"/vms?ed=2048\", \"tls\": \"tls\", \"sni\": \"${ARGO_DOMAIN}\", \"alpn\": \"\", \"fp\": \"randomized\", \"allowlnsecure\": \"false\"}"

# 将 VMESS JSON 转换为 Base64（跨平台兼容性处理）
if ! command -v base64 &>/dev/null; then
    error "base64 命令不可用，无法生成订阅链接"
fi

# 检查 base64 是否支持 -w 选项（GNU 版本支持，BusyBox 不支持）
if base64 -w 0 </dev/null >/dev/null 2>&1; then
    # GNU base64（Linux）- 支持 -w 0 选项
    VMESS_URL="vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)"
    FULL_URL="${VLESS_URL}\n${VMESS_URL}"
    ENCODED_URL=$(echo -e "$FULL_URL" | base64 -w 0)
else
    # BusyBox base64（Alpine）- 不支持 -w 选项，使用 tr 删除换行
    VMESS_URL="vmess://$(echo -n "$VMESS_JSON" | base64 | tr -d '\n')"
    FULL_URL="${VLESS_URL}\n${VMESS_URL}"
    ENCODED_URL=$(echo -e "$FULL_URL" | base64 | tr -d '\n')
fi

# 输出到文件
echo -n "$ENCODED_URL" > "$OUTPUT_FILE"

info "订阅链接已生成！"
info "VLESS: $VLESS_URL"
info "VMESS: $VMESS_URL"
hint "完整订阅内容已写入: $OUTPUT_FILE"
