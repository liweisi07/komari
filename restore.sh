#!/usr/bin/env bash

#===============================================================
#           Komari Dashboard Auto-Restore Script
#
# 此脚本用于自动检测和还原 Komari 面板备份数据
# ---------------------------------------------------------------
# 功能:
#   - 每分钟检测 GitHub 备份库中的最新备份文件
#   - 与本地记录比对，如果有新文件则自动还原
#   - 支持手动指定备份文件还原
#
# 使用方法:
#   - 自动还原（Supervisor/Cron 调用）: bash restore.sh a
#   - 手动还原（指定文件）: bash restore.sh {filename}
#   - 强制还原（忽略本地记录）: bash restore.sh f
#===============================================================

#---------------------------------------------------------------
# GitHub 仓库配置
#---------------------------------------------------------------
GH_BACKUP_USER="${GH_BACKUP_USER:-}"
GH_REPO="${GH_REPO:-}"
GH_PAT="${GH_PAT:-}"
GH_EMAIL="${GH_EMAIL:-}"

#---------------------------------------------------------------
# 面板工作目录配置
#---------------------------------------------------------------
WORK_DIR="${WORK_DIR:-/app}"
DATA_DIR="${WORK_DIR}/data"
RESTORE_FLAG_FILE="/tmp/last_restore"
RESTORE_LOG="/tmp/restore.log"

#---------------------------------------------------------------
# 脚本核心逻辑
#---------------------------------------------------------------

# 颜色定义
info() { echo -e "\033[32m\033[01m$*\033[0m"; }     # 绿色
error() { echo -e "\033[31m\033[01m$*\033[0m" && exit 1; } # 红色
hint() { echo -e "\033[33m\033[01m$*\033[0m"; }     # 黄色

# 日志函数
log() {
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S')] $*" >> "$RESTORE_LOG"
}

# 检查必需的环境变量
check_env() {
    if [ -z "$GH_BACKUP_USER" ] || [ -z "$GH_REPO" ] || [ -z "$GH_PAT" ]; then
        log "错误：备份相关环境变量未全部设置 (GH_BACKUP_USER, GH_REPO, GH_PAT)"
        exit 0  # 不报错退出，因为这是可选功能
    fi
}

# 获取远程仓库中最新的备份文件名（带重试机制）
get_latest_backup_filename() {
    local max_attempts=3
    local attempt=1
    local result=""
    
    while [ $attempt -le $max_attempts ]; do
        result=$(curl -s -H "Authorization: token $GH_PAT" \
            "https://api.github.com/repos/$GH_BACKUP_USER/$GH_REPO/contents/" \
            2>/dev/null | grep -oE 'komari-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}\.tar\.gz' | sort -r | head -n 1)
        
        if [ -n "$result" ]; then
            echo "$result"
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log "API 调用失败，2 秒后重试 (第 $attempt 次失败)"
            sleep 2
        fi
        attempt=$((attempt + 1))
    done
    
    log "API 调用失败，已重试 $max_attempts 次"
    echo ""
}

# 获取本地记录的最后还原文件名
get_last_restore_file() {
    if [ -f "$RESTORE_FLAG_FILE" ]; then
        cat "$RESTORE_FLAG_FILE"
    else
        echo ""
    fi
}

# 保存本次还原的文件名
save_restore_file() {
    echo "$1" > "$RESTORE_FLAG_FILE"
}

# 获取备份文件的下载 URL
get_download_url() {
    local filename="$1"
    curl -s -H "Authorization: token $GH_PAT" \
        "https://api.github.com/repos/$GH_BACKUP_USER/$GH_REPO/contents/$filename" \
        2>/dev/null | grep -o '"download_url": "[^"]*' | cut -d'"' -f4
}

# 执行还原操作
do_restore() {
    local backup_file="$1"
    
    info "开始还原备份: $backup_file"
    log "开始还原备份: $backup_file"
    
    # 获取下载链接
    download_url=$(get_download_url "$backup_file")
    
    if [ -z "$download_url" ]; then
        error "无法获取备份文件的下载链接: $backup_file"
    fi
    
    hint "正在下载备份文件..."
    download_path="/tmp/komari_restore.tar.gz"
    
    if ! wget -q -O "$download_path" "$download_url" 2>/dev/null; then
        error "下载备份文件失败"
    fi
    
    cd "$WORK_DIR" || error "无法进入工作目录: $WORK_DIR"
    
    hint "正在清理旧数据..."
    if [ -d "$DATA_DIR" ]; then
        rm -rf "$DATA_DIR"
    fi
    
    hint "正在解压备份文件..."
    if ! tar xzf "$download_path" -C "$WORK_DIR/" 2>/dev/null; then
        rm -f "$download_path"
        error "解压备份文件失败"
    fi
    
    rm -f "$download_path"
    
    # 记录本次还原
    save_restore_file "$backup_file"
    
    info "备份文件已成功还原: $backup_file"
    log "备份文件已成功还原: $backup_file"
}

# 自动还原模式（每分钟检测）
auto_restore() {
    check_env
    
    # 获取最新备份文件名
    latest_file=$(get_latest_backup_filename)
    
    if [ -z "$latest_file" ]; then
        log "未找到任何备份文件"
        exit 0
    fi
    
    # 获取本地记录的最后还原文件
    last_file=$(get_last_restore_file)
    
    # 比对：如果不同则还原
    if [ "$latest_file" != "$last_file" ]; then
        info "检测到新的备份文件: $latest_file (上次: $last_file)"
        log "检测到新的备份文件: $latest_file"
        do_restore "$latest_file"
    else
        log "本地与远程备份文件一致，无需还原"
    fi
}

# 手动还原模式（指定文件名）
manual_restore() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        error "请指定备份文件名: $0 {filename}"
    fi
    
    check_env
    do_restore "$backup_file"
}

# 强制还原模式（忽略本地记录）
force_restore() {
    check_env
    
    latest_file=$(get_latest_backup_filename)
    
    if [ -z "$latest_file" ]; then
        error "未找到任何备份文件"
    fi
    
    info "执行强制还原: $latest_file"
    log "执行强制还原: $latest_file"
    do_restore "$latest_file"
}

# --- 主逻辑 ---
case "${1:-}" in
    a)
        # 自动模式（Supervisor/Cron 每分钟调用）
        auto_restore
        ;;
    f)
        # 强制还原模式
        force_restore
        ;;
    "")
        # 无参数则显示帮助
        echo "使用方法:"
        echo "  $0 a              - 自动还原模式（Supervisor/Cron 每分钟调用）"
        echo "  $0 f              - 强制还原最新备份"
        echo "  $0 {filename}     - 手动还原指定备份文件"
        echo ""
        echo "示例:"
        echo "  $0 a                                              # 自动检测新备份并还原"
        echo "  $0 komari-2024-01-01-120000.tar.gz              # 还原指定文件"
        exit 1
        ;;
    *)
        # 手动指定文件名
        manual_restore "$1"
        ;;
esac
