#!/usr/bin/env bash

#===============================================================
#          Komari Dashboard Subscription Link Generator
#
# 此脚本为 Komari 面板生成 VLESS 和 VMESS 节点订阅链接
# 参考：https://github.com/Kiritocyz/Argo-Nezha-Service-Container
# ---------------------------------------------------------------
# 功能:
#   - 生成 VLESS 节点链接
#   - 生成 VMESS 节点链接 (Base64 编码)
#   - 生成完整的订阅链接并保存到文件
#
# 地址和端口说明：
#   - ARGO_DOMAIN: 服务器实际域名（可选，未设置时自动获取公网 IP）
#   - CF_IP: Cloudflare 等 CDN 的优选 IP（用于优化连接，当未设置 ARGO_DOMAIN 时使用）
#   - CADDY_PROXY_PORT: Caddy 反向代理服务的实际端口（仅当未设置 ARGO_DOMAIN 时需要暴露）
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
CADDY_PROXY_PORT="${CADDY_PROXY_PORT:-8443}"

# 检查必要的环境变量（UUID 是必需的）
if [ -z "$UUID" ]; then
    hint "UUID 未设置，跳过生成订阅链接"
    exit 0
fi

# 如果 ARGO_DOMAIN 未设置，尝试使用公网 IP
if [ -z "$ARGO_DOMAIN" ]; then
    hint "ARGO_DOMAIN 未设置，尝试获取服务器公网 IP..."
    PUBLIC_IP=$(get_public_ip)
    if [ -n "$PUBLIC_IP" ]; then
        ARGO_DOMAIN="$PUBLIC_IP"
        hint "使用公网 IP: $ARGO_DOMAIN"
    else
        hint "无法获取公网 IP，跳过生成订阅链接"
        exit 0
    fi
fi

# 获取国家代码
COUNTRY_CODE=$(get_country_code)
info "检测到国家代码: $COUNTRY_CODE"

# 协议类型定义
XIEYI='vl'
XIEYI2='vm'

# 生成 VLESS 链接
# 连接到 CF_IP:CADDY_PROXY_PORT（用于未设置 ARGO_DOMAIN 的情况），SNI 指向 ARGO_DOMAIN
VLESS_URL="vless://${UUID}@${CF_IP}:${CADDY_PROXY_PORT}?path=%2F${XIEYI}s%3Fed%3D2048&security=tls&encryption=none&host=${ARGO_DOMAIN}&type=ws&sni=${ARGO_DOMAIN}#${COUNTRY_CODE}-${SUB_NAME}-${XIEYI}"

# 生成 VMESS JSON
# add: CF_IP（用于未设置 ARGO_DOMAIN 的情况），port: CADDY_PROXY_PORT，host/sni: ARGO_DOMAIN
VMESS_JSON="{ \"v\": \"2\", \"ps\": \"${COUNTRY_CODE}-${SUB_NAME}-${XIEYI2}\", \"add\": \"${CF_IP}\", \"port\": \"${CADDY_PROXY_PORT}\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"${ARGO_DOMAIN}\", \"path\": \"/vms?ed=2048\", \"tls\": \"tls\", \"sni\": \"${ARGO_DOMAIN}\", \"alpn\": \"\", \"fp\": \"randomized\", \"allowlnsecure\": \"false\"}"

# 将 VMESS JSON 转换为 Base64
if command -v base64 &> /dev/null; then
    VMESS_URL="vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)"
    
    # 生成完整订阅链接 (两个 URL 分别放在不同行)
    FULL_URL="${VLESS_URL}\n${VMESS_URL}"
    ENCODED_URL=$(echo -e "$FULL_URL" | base64 -w 0)
    
    # 输出到文件
    echo -n "$ENCODED_URL" > "$OUTPUT_FILE"
    
    info "订阅链接已生成！"
    info "VLESS: $VLESS_URL"
    info "VMESS: $VMESS_URL"
    hint "完整订阅内容已写入: $OUTPUT_FILE"
else
    error "base64 命令不可用！"
fi
