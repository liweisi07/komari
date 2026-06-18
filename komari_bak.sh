#!/usr/bin/env bash

#===============================================================
#               Komari Dashboard Backup Script
#
# 此脚本专为在 Docker 版 Komari 面板数据的备份还原设计
# ---------------------------------------------------------------
# 功能:
#   - 备份: 打包并备份 Komari 面板的数据目录至私有 GitHub 仓库。
#   - 还原: 从 GitHub 仓库拉取最新的备份文件并恢复至面板。
#
# 使用方法:
#   - 备份 (由 Cron 自动调用): bash komari_bak.sh bak
#   - 还原 (手动调用): bash komari_bak.sh res
#===============================================================

#---------------------------------------------------------------
# GITHUB 仓库配置 (请务必修改为自己的信息，建议通过环境变量传递)
#---------------------------------------------------------------
GH_BACKUP_USER="${GH_BACKUP_USER:-your_github_username}"
GH_REPO="${GH_REPO:-your_private_repo_name}"
GH_PAT="${GH_PAT:-your_github_personal_access_token}"
GH_EMAIL="${GH_EMAIL:-your_github_email@example.com}"

#---------------------------------------------------------------
# 备份相关配置
#---------------------------------------------------------------
BACKUP_DAYS="${BACKUP_DAYS:-10}"  # 保留最近 N 天的备份文件

#---------------------------------------------------------------
# 面板工作目录配置 (与 Dockerfile 中 Komari 的工作路径保持一致)
#---------------------------------------------------------------
WORK_DIR="/app"
DATA_DIR="${WORK_DIR}/data"

#---------------------------------------------------------------
# 脚本核心逻辑
#---------------------------------------------------------------

# 颜色定义
info() { echo -e "\033[32m\033[01m$*\033[0m"; }     # 绿色
error() { echo -e "\033[31m\033[01m$*\033[0m" && exit 1; } # 红色
hint() { echo -e "\033[33m\033[01m$*\033[0m"; }     # 黄色

# 备份函数
do_backup() {
    info "============== 开始执行 Komari 备份任务 =============="

    if [ "$GH_PAT" = "your_github_personal_access_token" ] || [ -z "$GH_PAT" ]; then
        error "GitHub PAT 未正确设置。请确保在运行容器时使用 -e GH_PAT=... 正确设置。"
    fi
    cd "$WORK_DIR" || error "无法进入工作目录: $WORK_DIR"

    hint "正在克隆备份仓库..."
    BACKUP_TEMP_DIR="/tmp/$GH_REPO"
    [ -d "$BACKUP_TEMP_DIR" ] && rm -rf "$BACKUP_TEMP_DIR"
    
    # 使用 PAT 克隆私有仓库
    if ! git clone "https://$GH_PAT@github.com/$GH_BACKUP_USER/$GH_REPO.git" --depth 1 "$BACKUP_TEMP_DIR"; then
        error "克隆 GitHub 仓库失败。请检查 GH_PAT 或网络连接。"
    fi

    TIME=$(date -u "+%Y-%m-%d-%H%M%S")
    BACKUP_FILE="komari-$TIME.tar.gz"
    
    hint "正在压缩数据目录: $DATA_DIR"
    
    # 检查数据目录是否存在
    if [ ! -d "$DATA_DIR" ]; then
        error "备份数据目录不存在: $DATA_DIR"
    fi
    
    tar czvf "$BACKUP_TEMP_DIR/$BACKUP_FILE" -C "$WORK_DIR" data/

    if [ ! -s "$BACKUP_TEMP_DIR/$BACKUP_FILE" ]; then
        error "压缩文件失败或文件为空。"
    fi
    
    # 验证备份文件完整性
    if ! tar -tzf "$BACKUP_TEMP_DIR/$BACKUP_FILE" > /dev/null 2>&1; then
        error "备份文件已损坏，无法验证 tar 文件完整性。"
    fi
    
    info "文件已压缩为: $BACKUP_FILE"

    cd "$BACKUP_TEMP_DIR" || error "进入临时仓库目录失败。"
    
    hint "正在清理旧备份，保留最近 $BACKUP_DAYS 天的数据..."
    # 根据文件名中的时间戳判断文件年龄，删除超过 BACKUP_DAYS 天的备份
    # 使用 UTC 时间计算截止日期
    CUTOFF_DATE=$(date -u -d "$BACKUP_DAYS days ago" "+%Y-%m-%d" 2>/dev/null || date -u -v-${BACKUP_DAYS}d "+%Y-%m-%d")
    find ./ -name 'komari-*.tar.gz' -type f | while read file; do
        FILE_DATE=$(echo "$file" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
        if [ "$FILE_DATE" \< "$CUTOFF_DATE" ]; then
            rm -f "$file"
        fi
    done
    
    # 记录最新的备份文件名
    echo "$BACKUP_FILE" > README.md

    # 配置 Git 用户信息并提交
    git config user.name "$GH_BACKUP_USER"
    git config user.email "$GH_EMAIL"
    git add .
    # 检查是否有文件变动再提交
    if git status --porcelain | grep -q .; then
        git commit -m "Backup at $TIME"
    else
        info "无新文件或变更需要提交。"
        rm -rf "$BACKUP_TEMP_DIR"
        info "============== 备份任务执行完毕 (无变更) =============="
        return
    fi
    
    if git push -f -u origin main; then
        info "备份文件和 README.md 已成功上传至 GitHub！"
    else
        error "上传失败。请检查网络或 GitHub PAT 权限。"
    fi

    rm -rf "$BACKUP_TEMP_DIR"
    info "============== 备份任务执行完毕 =============="
}

# --- 主逻辑 ---
case "$1" in
    bak)
        do_backup
        ;;
    *)
        echo "使用方法:"
        echo "  $0 bak   - 执行备份 (Cron 自动调用)"
        echo ""
        echo "注意：还原功能请使用 restore.sh"
        exit 1
        ;;
esac
