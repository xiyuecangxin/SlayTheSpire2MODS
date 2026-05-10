#!/bin/bash
# ============================================================
#  杀戮尖塔2 模组管理器 / Slay the Spire 2 Mod Manager (macOS)
#  Author: 皮一下就很凡@Bilibili
#  https://space.bilibili.com/26786884
#  macOS 版本 — 由 PowerShell 脚本移植
#
#  使用方法：
#    1. 打开「终端」应用
#    2. 输入 bash 加一个空格，然后把本文件拖进终端窗口，回车运行
#    或者: chmod +x 安装与卸载脚本-Mac.sh && ./安装与卸载脚本-Mac.sh
# ============================================================

set -euo pipefail

# ── Shell 兼容性 ──
# macOS 默认 shell 是 Zsh（数组从 1 开始），本脚本使用 Bash 语法（数组从 0 开始）
# 如果用户在 Zsh 中运行，自动切换到 Bash 重新执行
if [ -n "${ZSH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

# ── 环境检查 ──
if [[ "$(uname)" != "Darwin" ]]; then
    echo "[!] 本脚本仅支持 macOS，当前系统: $(uname)" >&2
    exit 1
fi

# ── 颜色定义 ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# ── 常量 ──
VERSION="2.0.1"
STS2_APPID="2868840"
STS2_DIRNAME="Slay the Spire 2"
STS2_APP="SlayTheSpire2.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/modmanager.json"
MODS_SOURCE="${SCRIPT_DIR}/Mods"
SAVE_ROOT="${HOME}/Library/Application Support/SlayTheSpire2/steam"
LOG_DIR="${SCRIPT_DIR}/logs"
MAX_LOGS=3
UPDATE_API=$(echo "aHR0cHM6Ly8xMzIzOTE5NzQ3LWVjeXh5MzZyYncuYXAtc2hhbmdoYWkudGVuY2VudHNjZi5jb20=" | base64 --decode)

# ── python3 检测（在线更新依赖 python3 解析 JSON）──
HAS_PYTHON3=false
if command -v python3 &>/dev/null; then
    HAS_PYTHON3=true
fi

# ── 在线更新状态 ──
LAST_CHECK_FILE="/tmp/sts2_check_result.json"
LAST_CHECK_UPDATES_COUNT=0

# ── 日志管理 ──
LOG_FILE=""

start_logging() {
    mkdir -p "$LOG_DIR"

    # 清理旧日志，只保留最近 MAX_LOGS - 1 个
    local old_logs
    old_logs=$(ls -1t "$LOG_DIR"/modmanager_*.log 2>/dev/null || true)
    local count
    count=$(echo "$old_logs" | grep -c '.' 2>/dev/null || echo 0)
    if [ "$count" -ge "$MAX_LOGS" ]; then
        echo "$old_logs" | tail -n +$((MAX_LOGS)) | while read -r f; do
            [ -n "$f" ] && rm -f "$f"
        done
    fi

    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    LOG_FILE="${LOG_DIR}/modmanager_${timestamp}.log"
    # 使用 tee 和 exec 进行日志记录
    exec > >(tee -a "$LOG_FILE") 2>&1
}

# ── 输出辅助（全部输出到 stderr，避免被 $() 捕获污染返回值） ──
write_title() {
    echo "" >&2
    echo -e "  ${CYAN}$1${NC}" >&2
    local len=${#1}
    printf "  ${DIM}" >&2
    printf '─%.0s' $(seq 1 $((len + 2))) >&2
    printf "${NC}\n" >&2
    echo "" >&2
}

write_ok()   { echo -e "  ${GREEN}[√] $1${NC}" >&2; }
write_warn() { echo -e "  ${YELLOW}[!] $1${NC}" >&2; }
write_err()  { echo -e "  ${RED}[!] $1${NC}" >&2; }
write_info() { echo -e "  $1" >&2; }
write_dim()  { echo -e "  ${DIM}$1${NC}" >&2; }

pause_and_return() {
    echo "" >&2
    echo -ne "  ${DIM}按回车键继续...${NC}" >&2
    read -r
    echo "" >&2
}

read_choice() {
    echo "" >&2
    echo -ne "  ${WHITE}$1${NC}" >&2
    read -r REPLY
}

# ── 配置管理 ──
GAME_DIR=""

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # 从 JSON 中提取 GameDir 的值（纯 bash/sed）
        local dir
        dir=$(sed -n 's/.*"GameDir"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' "$CONFIG_FILE" 2>/dev/null || echo "")
        GAME_DIR="$dir"
    fi
}

save_config() {
    cat > "$CONFIG_FILE" <<EOF
{
    "GameDir": "${GAME_DIR}"
}
EOF
}

get_game_dir() {
    if [ -n "$GAME_DIR" ]; then
        if [ -d "${GAME_DIR}/${STS2_APP}" ]; then
            echo "$GAME_DIR"
            return 0
        else
            GAME_DIR=""
            save_config
        fi
    fi
    return 1
}

# ── 获取模组安装目录（.app 包内） ──
get_mods_dir() {
    local game_dir="$1"
    echo "${game_dir}/${STS2_APP}/Contents/MacOS/mods"
}

# ── 自动检测游戏目录 ──
find_game_dir() {
    local steam_path="${HOME}/Library/Application Support/Steam"

    if [ -d "$steam_path" ]; then
        # 1. 检查 Steam 默认库
        local candidate="${steam_path}/steamapps/common/${STS2_DIRNAME}"
        if [ -d "${candidate}/${STS2_APP}" ]; then
            echo "$candidate"
            return 0
        fi

        # 2. 解析 libraryfolders.vdf（包含所有 Steam 库路径）
        local vdf_paths=(
            "${steam_path}/steamapps/libraryfolders.vdf"
            "${steam_path}/config/libraryfolders.vdf"
        )
        for vdf in "${vdf_paths[@]}"; do
            if [ -f "$vdf" ]; then
                local lib_paths
                lib_paths=$(grep -oE '"path"\s+"[^"]+"' "$vdf" 2>/dev/null | sed 's/"path"[[:space:]]*"//;s/"$//' || true)
                while IFS= read -r lib_path; do
                    [ -z "$lib_path" ] && continue
                    # 处理转义的反斜杠
                    lib_path=$(echo "$lib_path" | sed 's|\\\\|/|g')
                    candidate="${lib_path}/steamapps/common/${STS2_DIRNAME}"
                    if [ -d "${candidate}/${STS2_APP}" ]; then
                        echo "$candidate"
                        return 0
                    fi
                done <<< "$lib_paths"
                break
            fi
        done
    fi

    # 3. 暴力搜索常见路径
    local search_paths=(
        "/Applications/Steam"
        "/Applications/SteamLibrary"
        "${HOME}/Games/Steam"
        "${HOME}/Games/SteamLibrary"
        "/Volumes"
    )

    for base in "${search_paths[@]}"; do
        if [ -d "$base" ]; then
            local candidate="${base}/steamapps/common/${STS2_DIRNAME}"
            if [ -d "${candidate}/${STS2_APP}" ]; then
                echo "$candidate"
                return 0
            fi
        fi
    done

    # 4. 搜索 /Volumes 下的外部驱动器
    if [ -d "/Volumes" ]; then
        for vol in /Volumes/*/; do
            for sub in "SteamLibrary" "Steam" "Games/Steam" "Games/SteamLibrary"; do
                local candidate="${vol}${sub}/steamapps/common/${STS2_DIRNAME}"
                if [ -d "${candidate}/${STS2_APP}" ]; then
                    echo "$candidate"
                    return 0
                fi
            done
        done
    fi

    return 1
}

# ── 确保游戏目录可用 ──
ensure_game_dir() {
    local dir
    if dir=$(get_game_dir); then
        echo "$dir"
        return 0
    fi

    write_info "游戏目录未设置或无效，正在自动检测..."
    if dir=$(find_game_dir); then
        write_ok "自动检测成功: $dir"
        GAME_DIR="$dir"
        save_config
        echo "$dir"
        return 0
    fi

    write_warn "自动检测失败，请手动指定游戏目录。"
    set_game_dir_manual
}

set_game_dir_manual() {
    echo "" >&2
    write_info "请输入杀戮尖塔2的安装目录（包含 ${STS2_APP} 的文件夹）"
    write_dim "例如: ${HOME}/Library/Application Support/Steam/steamapps/common/Slay the Spire 2"
    write_dim "输入 0 返回"
    echo "" >&2
    echo -ne "  路径: " >&2
    read -r path
    path=$(echo "$path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^"//;s/"$//')

    if [ "$path" = "0" ] || [ -z "$path" ]; then
        return 1
    fi

    if [ -d "${path}/${STS2_APP}" ]; then
        GAME_DIR="$path"
        save_config
        write_ok "游戏目录已设置: $path"
        echo "$path"
        return 0
    else
        write_err "未在该目录找到 ${STS2_APP}，请检查路径。"
        return 1
    fi
}

# ── 获取 Steam ID ──
get_steam_id() {
    if [ ! -d "$SAVE_ROOT" ]; then
        write_err "未找到存档目录: ${SAVE_ROOT}"
        write_info "请先运行一次游戏以创建存档。"
        return 1
    fi

    local ids=()
    while IFS= read -r d; do
        [ -n "$d" ] && ids+=("$(basename "$d")")
    done < <(find "$SAVE_ROOT" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)

    if [ ${#ids[@]} -eq 0 ]; then
        write_err "未找到任何 Steam 用户存档。"
        return 1
    fi

    if [ ${#ids[@]} -eq 1 ]; then
        echo "${ids[0]}"
        return 0
    fi

    # 多个用户
    write_info "检测到多个 Steam 账号:"
    echo "" >&2
    for i in "${!ids[@]}"; do
        write_info "  $((i+1)). ${ids[$i]}"
    done
    read_choice "请选择账号 [1-${#ids[@]}]: "
    local idx=$((REPLY - 1))
    if [ "$idx" -ge 0 ] && [ "$idx" -lt ${#ids[@]} ]; then
        echo "${ids[$idx]}"
        return 0
    fi
    return 1
}

# ── 获取存档槽位信息 ──
# 返回格式: has_data|last_modified|path
get_profile_info() {
    local steam_id="$1"
    local type="$2"
    local profile_id="$3"

    local base
    if [ "$type" = "normal" ]; then
        base="${SAVE_ROOT}/${steam_id}/profile${profile_id}/saves"
    else
        base="${SAVE_ROOT}/${steam_id}/modded/profile${profile_id}/saves"
    fi

    local progress_file="${base}/progress.save"
    if [ -f "$progress_file" ]; then
        local last_modified
        last_modified=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$progress_file" 2>/dev/null || echo "unknown")
        echo "true|${last_modified}|${base}"
    else
        echo "false||${base}"
    fi
}

# ── 扫描可安装模组 ──
get_available_mods() {
    if [ ! -d "$MODS_SOURCE" ]; then
        return
    fi
    find "$MODS_SOURCE" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort
}

# ── 扫描已安装模组 ──
get_installed_mods() {
    local mods_dir
    mods_dir=$(get_mods_dir "$1")
    if [ ! -d "$mods_dir" ]; then
        return
    fi
    find "$mods_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort
}

# ── 从 JSON 文件读取字符串字段 ──
get_json_field_from_file() {
    local manifest_path="$1"
    local field="$2"
    if [ -f "$manifest_path" ]; then
        sed -n 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' "$manifest_path" 2>/dev/null | head -1
    fi
}

# ── 读取 v0.99+ 根 manifest（<ModId>.json） ──
get_modern_manifest_path() {
    local mod_dir="$1"
    local manifest
    for manifest in "$mod_dir"/*.json; do
        [ -e "$manifest" ] || continue
        if [ "$(basename "$manifest")" = "mod_manifest.json" ]; then
            continue
        fi
        if [ -n "$(get_json_field_from_file "$manifest" "id")" ]; then
            echo "$manifest"
            return
        fi
    done
}

# ── 读取首选 manifest 字段：modern id 优先，legacy pck_name fallback ──
get_mod_manifest_field() {
    local mod_dir="$1"
    local field="$2"
    local modern_manifest
    modern_manifest=$(get_modern_manifest_path "$mod_dir")
    if [ -n "$modern_manifest" ]; then
        local modern_field="$field"
        if [ "$field" = "pck_name" ]; then
            modern_field="id"
        fi
        local value
        value=$(get_json_field_from_file "$modern_manifest" "$modern_field")
        if [ -n "$value" ]; then
            echo "$value"
            return
        fi
    fi

    local legacy_manifest="${mod_dir}/mod_manifest.json"
    get_json_field_from_file "$legacy_manifest" "$field"
}

# ── 推断安装目录名 ──
get_install_name() {
    local mod_dir="$1"
    # 优先级: modern manifest.id > legacy manifest.pck_name > DLL 文件名 > 文件夹名
    local mod_id
    mod_id=$(get_mod_manifest_field "$mod_dir" "pck_name")
    if [ -n "$mod_id" ]; then
        echo "$mod_id"
        return
    fi
    # 从 DLL 文件名推断
    local dll
    dll=$(find "$mod_dir" -maxdepth 1 -name "*.dll" -not -name "*.bak*" -type f 2>/dev/null | head -1)
    if [ -n "$dll" ]; then
        basename "$dll" .dll
        return
    fi
    # 最后用文件夹名
    basename "$mod_dir"
}

# ── 格式化模组显示名 ──
format_mod_label() {
    local mod_dir="$1"
    local dir_name
    dir_name=$(basename "$mod_dir")
    local name ver author label

    name=$(get_mod_manifest_field "$mod_dir" "name")
    ver=$(get_mod_manifest_field "$mod_dir" "version")
    author=$(get_mod_manifest_field "$mod_dir" "author")

    if [ -n "$name" ] || [ -n "$ver" ]; then
        label="$dir_name"
        if [ -n "$name" ] && [ "$name" != "$dir_name" ]; then
            label="${name} (${dir_name})"
        fi
        if [ -n "$ver" ]; then
            label="${label} v${ver}"
        else
            label="${label} v?"
        fi
        if [ -n "$author" ]; then
            label="${label} by ${author}"
        fi
        echo "$label"
    else
        local install_name
        install_name=$(get_install_name "$mod_dir")
        if [ "$install_name" != "$dir_name" ]; then
            echo "${install_name} (${dir_name}) v?"
        else
            echo "${dir_name} v?"
        fi
    fi
}

# ============================================================
#  功能: 安装模组
# ============================================================
install_mod() {
    local game_dir
    if ! game_dir=$(ensure_game_dir); then
        write_err "无法确定游戏目录，安装中止。"
        pause_and_return
        return
    fi

    write_title "安装模组"

    local mods=()
    while IFS= read -r m; do
        [ -n "$m" ] && mods+=("$m")
    done < <(get_available_mods)

    if [ ${#mods[@]} -eq 0 ]; then
        write_warn "未找到可安装的模组。"
        write_info "请确保 Mods 文件夹与本脚本在同一目录下。"
        pause_and_return
        return
    fi

    local mods_dir
    mods_dir=$(get_mods_dir "$game_dir")
    local installed_names=()
    if [ -d "$mods_dir" ]; then
        while IFS= read -r d; do
            [ -n "$d" ] && installed_names+=("$(basename "$d")")
        done < <(get_installed_mods "$game_dir")
    fi

    write_info "可用模组:"
    echo ""
    for i in "${!mods[@]}"; do
        local mod="${mods[$i]}"
        local label
        label=$(format_mod_label "$mod")
        local install_name
        install_name=$(get_install_name "$mod")

        local is_installed=false
        for iname in "${installed_names[@]:-}"; do
            if [ "$iname" = "$install_name" ]; then
                is_installed=true
                break
            fi
        done

        if $is_installed; then
            # 检查版本差异
            local inst_dir="${mods_dir}/${install_name}"
            local inst_ver src_ver
            inst_ver=$(get_mod_manifest_field "$inst_dir" "version")
            src_ver=$(get_mod_manifest_field "$mod" "version")

            if [ -n "$src_ver" ] && [ -n "$inst_ver" ] && [ "$src_ver" != "$inst_ver" ]; then
                echo -e "    $((i+1)). ${YELLOW}${label}  [可更新: v${inst_ver} -> v${src_ver}]${NC}"
            else
                echo -e "    $((i+1)). ${DIM}${label}  [已安装]${NC}"
            fi
        else
            echo -e "    $((i+1)). ${WHITE}${label}${NC}"
        fi
    done
    echo ""
    echo -e "    ${CYAN}A. 安装全部${NC}"
    echo -e "    ${DIM}0. 返回主菜单${NC}"
    read_choice "请选择要安装的模组 [编号/逗号分隔多个/A/0]: "
    local choice="$REPLY"

    if [ "$choice" = "0" ]; then return; fi

    local to_install=()
    if [ "$choice" = "A" ] || [ "$choice" = "a" ]; then
        to_install=("${mods[@]}")
    else
        # 支持英文逗号、中文逗号、空格分隔多个编号
        local normalized
        normalized=$(echo "$choice" | sed 's/，/,/g; s/ /,/g')
        local has_invalid=false
        IFS=',' read -ra nums <<< "$normalized"
        for num in "${nums[@]}"; do
            num=$(echo "$num" | tr -d ' ')
            [ -z "$num" ] && continue
            local idx=$((num - 1))
            if [ "$idx" -ge 0 ] && [ "$idx" -lt ${#mods[@]} ] 2>/dev/null; then
                to_install+=("${mods[$idx]}")
            else
                write_err "无效编号: ${num}"
                has_invalid=true
            fi
        done
        if [ ${#to_install[@]} -eq 0 ]; then
            write_err "没有有效的选择。"
            pause_and_return
            return
        fi
        if $has_invalid; then
            write_info "将跳过无效编号，继续安装有效的模组。"
        fi
    fi

    local dest_root
    dest_root=$(get_mods_dir "$game_dir")
    mkdir -p "$dest_root"

    for mod in "${to_install[@]}"; do
        echo ""
        local install_name
        install_name=$(get_install_name "$mod")
        local display_name
        display_name=$(format_mod_label "$mod")

        write_info "正在安装: ${display_name} ..."
        if [ "$install_name" != "$(basename "$mod")" ]; then
            write_dim "  安装目录: ${install_name}"
        fi

        local dest_dir="${dest_root}/${install_name}"
        mkdir -p "$dest_dir"

        local file_count=0
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            local fname
            fname=$(basename "$f")
            if cp -f "$f" "${dest_dir}/${fname}" 2>/dev/null; then
                echo -e "    ${GREEN}[√] ${fname}${NC}"
            else
                echo -e "    ${RED}[!] 无法复制 ${fname}${NC}"
            fi
            file_count=$((file_count + 1))
        done < <(find "$mod" -maxdepth 1 -type f 2>/dev/null)

        write_ok "${display_name} 安装完成 (共 ${file_count} 个文件)"
    done

    # 安装后自动开启模组开关
    echo ""
    echo -e "  ${DIM}──────────────────────────────────${NC}"
    write_ok "模组安装完成！"
    if enable_mods_in_settings; then
        write_ok "已自动开启游戏中的模组开关。"
    fi
    echo ""
    write_info "提示: 杀戮尖塔2的模组存档和原版存档是分开的。"
    write_info "首次使用模组时，模组存档为空（新档）。"
    echo ""

    # 显示简要槽位概况
    local steam_id
    if steam_id=$(get_steam_id); then
        local has_normal=false
        local has_modded=false
        local normal_summary=""
        local modded_summary=""

        # 用于检测哪个更新
        local newest_normal_ts=0
        local newest_modded_ts=0

        for s in 1 2 3; do
            local ni mi
            ni=$(get_profile_info "$steam_id" "normal" "$s")
            mi=$(get_profile_info "$steam_id" "modded" "$s")

            local n_has n_time n_path
            IFS='|' read -r n_has n_time n_path <<< "$ni"
            local m_has m_time m_path
            IFS='|' read -r m_has m_time m_path <<< "$mi"

            if [ "$n_has" = "true" ]; then
                has_normal=true
                local short_time
                short_time=$(echo "$n_time" | sed 's/^[0-9]*-//' | sed 's/-/\//')
                normal_summary="${normal_summary}槽位${s}:有(${short_time})  "
                # 获取时间戳用于比较
                local n_ts
                n_ts=$(stat -f "%m" "${n_path}/progress.save" 2>/dev/null || echo 0)
                if [ "$n_ts" -gt "$newest_normal_ts" ]; then
                    newest_normal_ts=$n_ts
                fi
            else
                normal_summary="${normal_summary}槽位${s}:空  "
            fi

            if [ "$m_has" = "true" ]; then
                has_modded=true
                local short_time
                short_time=$(echo "$m_time" | sed 's/^[0-9]*-//' | sed 's/-/\//')
                modded_summary="${modded_summary}槽位${s}:有(${short_time})  "
                local m_ts
                m_ts=$(stat -f "%m" "${m_path}/progress.save" 2>/dev/null || echo 0)
                if [ "$m_ts" -gt "$newest_modded_ts" ]; then
                    newest_modded_ts=$m_ts
                fi
            else
                modded_summary="${modded_summary}槽位${s}:空  "
            fi
        done

        echo -e "  ${GREEN}原版存档: ${normal_summary}${NC}"
        echo -e "  ${YELLOW}模组存档: ${modded_summary}${NC}"
        echo ""

        if $has_normal; then
            local modded_newer=false
            if [ "$newest_modded_ts" -gt 0 ] && [ "$newest_normal_ts" -gt 0 ] && [ "$newest_modded_ts" -gt "$newest_normal_ts" ]; then
                modded_newer=true
            fi

            if $modded_newer; then
                echo ""
                write_warn "检测到模组存档比原版存档更新！"
                write_warn "你可能正在更新模组，复制原版存档会覆盖你现有的模组进度。"
                write_info "是否要将原版存档复制到模组存档？（会自动备份，但恢复较麻烦）"
                echo ""
                echo -ne "  ${YELLOW}复制存档？ [y/N]: ${NC}"
                read -r copy_choice
                copy_choice=$(echo "$copy_choice" | tr '[:lower:]' '[:upper:]')
                if [ "$copy_choice" = "Y" ]; then
                    copy_save_to_modded
                else
                    write_ok "已跳过存档复制。"
                fi
            else
                write_info "是否要将原版存档复制到模组存档？（会自动备份）"
                echo ""
                read_choice "复制存档？ [Y/N]: "
                if [ "$REPLY" = "Y" ] || [ "$REPLY" = "y" ]; then
                    copy_save_to_modded
                fi
            fi
        else
            write_dim "  没有原版存档可复制，跳过。"
        fi
    fi

    pause_and_return
}

# ============================================================
#  功能: 开启游戏中的模组开关 (修改 settings.save)
# ============================================================
enable_mods_in_settings() {
    if [ ! -d "$SAVE_ROOT" ]; then
        return 1
    fi

    local changed=false
    while IFS= read -r id_dir; do
        [ -z "$id_dir" ] && continue
        local settings_file="${id_dir}/settings.save"
        if [ -f "$settings_file" ]; then
            if grep -q '"mods_enabled"' "$settings_file" 2>/dev/null; then
                # 已有 mods_enabled 字段，替换为 true
                if grep -q '"mods_enabled"[[:space:]]*:[[:space:]]*false' "$settings_file" 2>/dev/null; then
                    sed -i '' 's/"mods_enabled"[[:space:]]*:[[:space:]]*false/"mods_enabled": true/' "$settings_file"
                    changed=true
                fi
            else
                # 没有 mod_settings 块，在最后一个 } 前插入
                sed -i '' 's/^}$/  ,"mod_settings": {\n    "mods_enabled": true\n  }\n}/' "$settings_file"
                changed=true
            fi
        fi
    done < <(find "$SAVE_ROOT" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)

    $changed && return 0 || return 1
}

# ============================================================
#  功能: 卸载模组（执行删除）
# ============================================================
remove_mod_files() {
    local mod_dirs=("$@")
    for mod in "${mod_dirs[@]}"; do
        local mod_name
        mod_name=$(basename "$mod")
        write_info "正在卸载: ${mod_name} ..."
        if rm -rf "$mod" 2>/dev/null; then
            write_ok "${mod_name} 已卸载"
        else
            write_err "卸载失败，请关闭游戏后重试。"
        fi
    done
}

# ============================================================
#  功能: 卸载模组
# ============================================================
uninstall_mod() {
    local game_dir
    if ! game_dir=$(ensure_game_dir); then
        write_err "无法确定游戏目录。"
        pause_and_return
        return
    fi

    write_title "卸载模组"

    local mods=()
    while IFS= read -r m; do
        [ -n "$m" ] && mods+=("$m")
    done < <(get_installed_mods "$game_dir")

    if [ ${#mods[@]} -eq 0 ]; then
        write_info "没有已安装的模组。"
        pause_and_return
        return
    fi

    write_info "已安装模组:"
    echo ""
    for i in "${!mods[@]}"; do
        local label
        label=$(format_mod_label "${mods[$i]}")
        echo -e "    $((i+1)). ${WHITE}${label}${NC}"
    done
    echo ""
    echo -e "    ${RED}A. 卸载全部${NC}"
    echo -e "    ${DIM}0. 返回主菜单${NC}"
    read_choice "请选择要卸载的模组 [编号/逗号分隔多个/A/0]: "
    local choice="$REPLY"

    if [ "$choice" = "0" ]; then return; fi

    local to_uninstall=()
    local uninstall_all=false
    if [ "$choice" = "A" ] || [ "$choice" = "a" ]; then
        to_uninstall=("${mods[@]}")
        uninstall_all=true
    else
        # 支持英文逗号、中文逗号、空格分隔多个编号
        local normalized
        normalized=$(echo "$choice" | sed 's/，/,/g; s/ /,/g')
        local has_invalid=false
        IFS=',' read -ra nums <<< "$normalized"
        for num in "${nums[@]}"; do
            num=$(echo "$num" | tr -d ' ')
            [ -z "$num" ] && continue
            local idx=$((num - 1))
            if [ "$idx" -ge 0 ] && [ "$idx" -lt ${#mods[@]} ] 2>/dev/null; then
                to_uninstall+=("${mods[$idx]}")
            else
                write_err "无效编号: ${num}"
                has_invalid=true
            fi
        done
        if [ ${#to_uninstall[@]} -eq 0 ]; then
            write_err "没有有效的选择。"
            pause_and_return
            return
        fi
    fi

    # 显示待卸载列表并确认
    echo ""
    write_info "将卸载以下模组:"
    for mod in "${to_uninstall[@]}"; do
        echo -e "    ${RED}· $(basename "$mod")${NC}"
    done
    read_choice "确认卸载 ${#to_uninstall[@]} 个模组？输入 Y 确认: "
    if [ "$REPLY" != "Y" ] && [ "$REPLY" != "y" ]; then
        write_info "已取消。"
        pause_and_return
        return
    fi

    if $uninstall_all; then
        # 全部卸载：直接清空整个 mods 目录（包括散落的 .dll/.pck 等文件）
        local mods_dir
        mods_dir=$(get_mods_dir "$game_dir")
        rm -rf "${mods_dir:?}/"*
        write_ok "mods 目录已清空。"
    else
        remove_mod_files "${to_uninstall[@]}"
        if [ ${#to_uninstall[@]} -gt 1 ]; then
            write_ok "已卸载 ${#to_uninstall[@]} 个模组。"
        fi
    fi

    pause_and_return
}

# ============================================================
#  功能: 查看已安装模组
# ============================================================
show_installed_mods() {
    local game_dir
    if ! game_dir=$(ensure_game_dir); then
        write_err "无法确定游戏目录。"
        pause_and_return
        return
    fi

    write_title "已安装模组"
    write_info "游戏目录: ${game_dir}"
    write_info "模组目录: $(get_mods_dir "$game_dir")"
    echo ""

    local mods=()
    while IFS= read -r m; do
        [ -n "$m" ] && mods+=("$m")
    done < <(get_installed_mods "$game_dir")

    if [ ${#mods[@]} -eq 0 ]; then
        write_info "没有已安装的模组。"
    else
        for mod in "${mods[@]}"; do
            local label
            label=$(format_mod_label "$mod")
            echo -e "    ${WHITE}${label}${NC}"
            while IFS= read -r f; do
                [ -z "$f" ] && continue
                local fname fsize size_str
                fname=$(basename "$f")
                # 跳过 .bak 文件
                case "$fname" in *.bak*) continue ;; esac
                fsize=$(stat -f "%z" "$f" 2>/dev/null || echo 0)
                if [ "$fsize" -gt 1048576 ]; then
                    size_str=$(echo "scale=1; $fsize / 1048576" | bc 2>/dev/null || echo "?")
                    size_str="${size_str} MB"
                elif [ "$fsize" -gt 1024 ]; then
                    size_str=$(echo "$fsize / 1024" | bc 2>/dev/null || echo "?")
                    size_str="${size_str} KB"
                else
                    size_str="${fsize} B"
                fi
                echo -e "      ${DIM}${fname}  (${size_str})${NC}"
            done < <(find "$mod" -maxdepth 1 -type f 2>/dev/null)
            echo ""
        done
        write_dim "共 ${#mods[@]} 个模组"
    fi

    pause_and_return
}

# ============================================================
#  功能: 存档管理
# ============================================================
show_save_menu() {
    while true; do
        clear
        write_title "存档管理"
        write_info "杀戮尖塔2 存档说明:"
        write_info "  · 原版存档与模组存档是完全分开的"
        write_info "  · 启用模组后，游戏会使用单独的模组存档"
        write_info "  · 首次使用模组时，模组存档为空（相当于新号）"
        write_info "  · 可以将原版存档复制到模组存档，保留已有进度"
        echo ""
        write_dim "存档目录: ${SAVE_ROOT}"
        echo ""
        echo -e "    ${CYAN}1. 复制原版存档到模组存档${NC}"
        echo -e "    ${DIM}   (推荐首次安装模组时使用)${NC}"
        echo -e "    ${CYAN}2. 复制模组存档回原版存档${NC}"
        echo -e "    ${DIM}   (推荐关闭模组时使用，同步进度回去)${NC}"
        echo "    3. 备份原版存档"
        echo "    4. 备份模组存档"
        echo "    5. 查看存档状态"
        echo "    6. 恢复备份"
        echo -e "    ${DIM}0. 返回主菜单${NC}"

        read_choice "请选择 [0-6]: "
        case "$REPLY" in
            1) copy_save_to_modded; pause_and_return ;;
            2) copy_save_to_normal; pause_and_return ;;
            3) backup_save "normal"; pause_and_return ;;
            4) backup_save "modded"; pause_and_return ;;
            5) show_save_status; pause_and_return ;;
            6) restore_backup; pause_and_return ;;
            0) return ;;
        esac
    done
}

show_save_status() {
    echo ""
    local steam_id
    if ! steam_id=$(get_steam_id); then return; fi

    echo ""
    echo -e "  ${CYAN}Steam ID: ${steam_id}${NC}"

    for type in "normal" "modded"; do
        local label color
        if [ "$type" = "normal" ]; then
            label="原版存档"
            color="$GREEN"
        else
            label="模组存档"
            color="$YELLOW"
        fi
        echo ""
        echo -e "  ${color}[${label}]${NC}"
        for i in 1 2 3; do
            local info
            info=$(get_profile_info "$steam_id" "$type" "$i")
            local has_data last_modified save_path
            IFS='|' read -r has_data last_modified save_path <<< "$info"

            if [ "$has_data" = "true" ]; then
                local detail="上次修改: ${last_modified}"
                if [ -f "${save_path}/current_run.save" ]; then
                    detail="${detail} | 有进行中的一局"
                fi
                echo -e "    ${color}槽位${i}: ${detail}${NC}"
            else
                echo -e "    ${DIM}槽位${i}: (空)${NC}"
            fi
        done
    done

    echo ""

    # 备份
    local backup_dir="${SAVE_ROOT}/${steam_id}/backups"
    echo -e "  ${MAGENTA}[备份]${NC}"
    if [ -d "$backup_dir" ]; then
        local backups=()
        while IFS= read -r d; do
            [ -n "$d" ] && backups+=("$d")
        done < <(find "$backup_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort -r)

        if [ ${#backups[@]} -eq 0 ]; then
            write_dim "    (无备份)"
        else
            for bk in "${backups[@]}"; do
                local bk_name
                bk_name=$(basename "$bk")
                local file_count
                file_count=$(find "$bk" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
                local profile_label=""
                if [[ "$bk_name" =~ _p([0-9])_ ]]; then
                    profile_label="槽位${BASH_REMATCH[1]}, "
                fi
                echo -e "    ${DIM}${bk_name}  (${profile_label}${file_count} 个文件)${NC}"
            done
        fi
    else
        write_dim "    (无备份)"
    fi
}

copy_save_to_modded() {
    echo ""
    write_info "── 复制原版存档到模组存档 ──"
    echo ""

    local steam_id
    if ! steam_id=$(get_steam_id); then return; fi

    echo -e "  ${CYAN}Steam ID: ${steam_id}${NC}"
    echo ""

    # 扫描所有 3 个槽位
    local normal_infos=() modded_infos=()
    local normal_has=() normal_time=() normal_path=()
    local modded_has=() modded_time=() modded_path=()

    for i in 1 2 3; do
        local ni mi
        ni=$(get_profile_info "$steam_id" "normal" "$i")
        mi=$(get_profile_info "$steam_id" "modded" "$i")

        IFS='|' read -r n_h n_t n_p <<< "$ni"
        IFS='|' read -r m_h m_t m_p <<< "$mi"

        normal_has+=("$n_h"); normal_time+=("$n_t"); normal_path+=("$n_p")
        modded_has+=("$m_h"); modded_time+=("$m_t"); modded_path+=("$m_p")
    done

    # 检查是否有原版存档
    local has_any_normal=false
    for i in 0 1 2; do
        if [ "${normal_has[$i]}" = "true" ]; then
            has_any_normal=true
            break
        fi
    done

    if ! $has_any_normal; then
        write_err "没有可复制的原版存档。请先运行一次原版游戏。"
        return
    fi

    # 自动选择: 来源 = 第一个非空原版, 目标 = 第一个空模组（或槽位1）
    local src_slot=0
    for i in 0 1 2; do
        if [ "${normal_has[$i]}" = "true" ]; then
            src_slot=$((i + 1))
            break
        fi
    done

    local dst_slot=0
    for i in 0 1 2; do
        if [ "${modded_has[$i]}" != "true" ]; then
            dst_slot=$((i + 1))
            break
        fi
    done
    [ "$dst_slot" -eq 0 ] && dst_slot=1

    # 交互式选择循环
    while true; do
        # 显示原版存档
        echo -e "  ${GREEN}[原版存档 — 来源]${NC}"
        for i in 0 1 2; do
            local slot=$((i + 1))
            local arrow=""
            [ "$slot" -eq "$src_slot" ] && arrow=" ◄ 来源"

            if [ "${normal_has[$i]}" = "true" ]; then
                echo -ne "    ${GREEN}槽位${slot}: 有存档  ${normal_time[$i]}${NC}"
                [ -n "$arrow" ] && echo -ne "  ${CYAN}${arrow}${NC}"
                echo ""
            else
                echo -e "    ${DIM}槽位${slot}: (空)${NC}"
            fi
        done

        echo ""

        # 显示模组存档
        echo -e "  ${YELLOW}[模组存档 — 目标]${NC}"
        for i in 0 1 2; do
            local slot=$((i + 1))
            local arrow=""
            [ "$slot" -eq "$dst_slot" ] && arrow=" ◄ 目标"

            if [ "${modded_has[$i]}" = "true" ]; then
                echo -ne "    ${YELLOW}槽位${slot}: 有存档  ${modded_time[$i]}${NC}"
                [ -n "$arrow" ] && echo -ne "  ${CYAN}${arrow}${NC}"
                echo ""
            else
                echo -ne "    ${DIM}槽位${slot}: (空)${NC}"
                [ -n "$arrow" ] && echo -ne "  ${CYAN}${arrow}${NC}"
                echo ""
            fi
        done

        echo ""
        echo -e "  ${DIM}─────────────────────────────────${NC}"
        local dst_note=""
        if [ "${modded_has[$((dst_slot-1))]}" = "true" ]; then
            dst_note=" (将覆盖，自动备份)"
        fi
        echo -e "  ${CYAN}计划: 原版槽位${src_slot} → 模组槽位${dst_slot}${dst_note}${NC}"
        echo ""
        echo "    S. 更改来源槽位 (当前: ${src_slot})"
        echo "    D. 更改目标槽位 (当前: ${dst_slot})"
        echo -e "    ${CYAN}Y. 确认执行${NC}"
        echo -e "    ${DIM}0. 取消${NC}"

        read_choice "请选择 [S/D/Y/0]: "
        local choice="$REPLY"

        if [ "$choice" = "0" ]; then write_info "已取消。"; return; fi
        if [ "$choice" = "Y" ] || [ "$choice" = "y" ]; then break; fi

        if [ "$choice" = "S" ] || [ "$choice" = "s" ]; then
            read_choice "选择来源槽位 [1-3]: "
            local pick="$REPLY"
            if [[ "$pick" =~ ^[1-3]$ ]]; then
                if [ "${normal_has[$((pick-1))]}" = "true" ]; then
                    src_slot=$pick
                    write_ok "来源已更改为: 原版槽位${src_slot}"
                else
                    write_warn "原版槽位${pick} 是空的，无法作为来源。"
                fi
            else
                write_warn "请输入 1-3。"
            fi
            continue
        fi

        if [ "$choice" = "D" ] || [ "$choice" = "d" ]; then
            read_choice "选择目标槽位 [1-3]: "
            local pick="$REPLY"
            if [[ "$pick" =~ ^[1-3]$ ]]; then
                dst_slot=$pick
                if [ "${modded_has[$((pick-1))]}" = "true" ]; then
                    write_warn "模组槽位${pick} 已有存档，执行时将自动备份后覆盖。"
                fi
                write_ok "目标已更改为: 模组槽位${dst_slot}"
            else
                write_warn "请输入 1-3。"
            fi
            continue
        fi
    done

    # 执行复制
    local src="${normal_path[$((src_slot-1))]}"
    local dst="${modded_path[$((dst_slot-1))]}"

    echo ""

    # 如果目标有数据，先备份
    if [ "${modded_has[$((dst_slot-1))]}" = "true" ]; then
        write_info "正在备份模组槽位${dst_slot} 的现有存档..."
        do_backup "$steam_id" "modded" "auto_before_copy" "$dst_slot"
        echo ""
    fi

    # 创建目标目录
    mkdir -p "$dst"

    # 复制文件
    local copied=0

    # 复制存档文件
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        local fname
        fname=$(basename "$f")
        local dst_file="${dst}/${fname}"
        # 备份目标文件
        [ -f "$dst_file" ] && cp -f "$dst_file" "${dst_file}.before_copy" 2>/dev/null || true
        cp -f "$f" "$dst_file"
        echo -e "    ${GREEN}[√] ${fname}${NC}"
        copied=$((copied + 1))
    done < <(find "$src" -maxdepth 1 -type f 2>/dev/null)

    # 复制子目录 (如 history/)
    while IFS= read -r d; do
        [ -z "$d" ] && continue
        local dname
        dname=$(basename "$d")
        local dst_sub="${dst}/${dname}"
        cp -Rf "$d" "$dst_sub"
        local sub_count
        sub_count=$(find "$d" -type f 2>/dev/null | wc -l | tr -d ' ')
        echo -e "    ${GREEN}[√] ${dname}/ (${sub_count} 个文件)${NC}"
        copied=$((copied + sub_count))
    done < <(find "$src" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)

    echo ""
    if [ "$copied" -gt 0 ]; then
        write_ok "存档复制完成！原版槽位${src_slot} → 模组槽位${dst_slot}（共 ${copied} 个文件）"
        write_info "下次启用模组进入游戏时，请选择对应槽位使用复制的进度。"
    else
        write_warn "没有文件被复制。"
    fi
}

copy_save_to_normal() {
    echo ""
    write_info "── 复制模组存档回原版存档 ──"
    echo ""

    local steam_id
    if ! steam_id=$(get_steam_id); then return; fi

    echo -e "  ${CYAN}Steam ID: ${steam_id}${NC}"
    echo ""

    # 扫描所有 3 个槽位
    local normal_has=() normal_time=() normal_path=()
    local modded_has=() modded_time=() modded_path=()

    for i in 1 2 3; do
        local ni mi
        ni=$(get_profile_info "$steam_id" "normal" "$i")
        mi=$(get_profile_info "$steam_id" "modded" "$i")

        local n_h n_t n_p m_h m_t m_p
        IFS='|' read -r n_h n_t n_p <<< "$ni"
        IFS='|' read -r m_h m_t m_p <<< "$mi"

        normal_has+=("$n_h"); normal_time+=("$n_t"); normal_path+=("$n_p")
        modded_has+=("$m_h"); modded_time+=("$m_t"); modded_path+=("$m_p")
    done

    # 检查是否有模组存档
    local has_any_modded=false
    for i in 0 1 2; do
        if [ "${modded_has[$i]}" = "true" ]; then
            has_any_modded=true
            break
        fi
    done

    if ! $has_any_modded; then
        write_err "没有可复制的模组存档。请先使用模组运行一次游戏。"
        return
    fi

    # 自动选择: 来源 = 第一个非空模组, 目标 = 对应的原版槽位
    local src_slot=0
    for i in 0 1 2; do
        if [ "${modded_has[$i]}" = "true" ]; then
            src_slot=$((i + 1))
            break
        fi
    done

    local dst_slot=$src_slot

    # 交互式选择循环
    while true; do
        # 显示模组存档（来源）
        echo -e "  ${YELLOW}[模组存档 — 来源]${NC}"
        for i in 0 1 2; do
            local slot=$((i + 1))
            local arrow=""
            [ "$slot" -eq "$src_slot" ] && arrow=" ◄ 来源"

            if [ "${modded_has[$i]}" = "true" ]; then
                echo -ne "    ${YELLOW}槽位${slot}: 有存档  ${modded_time[$i]}${NC}"
                [ -n "$arrow" ] && echo -ne "  ${CYAN}${arrow}${NC}"
                echo ""
            else
                echo -e "    ${DIM}槽位${slot}: (空)${NC}"
            fi
        done

        echo ""

        # 显示原版存档（目标）
        echo -e "  ${GREEN}[原版存档 — 目标]${NC}"
        for i in 0 1 2; do
            local slot=$((i + 1))
            local arrow=""
            [ "$slot" -eq "$dst_slot" ] && arrow=" ◄ 目标"

            if [ "${normal_has[$i]}" = "true" ]; then
                echo -ne "    ${GREEN}槽位${slot}: 有存档  ${normal_time[$i]}${NC}"
                [ -n "$arrow" ] && echo -ne "  ${CYAN}${arrow}${NC}"
                echo ""
            else
                echo -ne "    ${DIM}槽位${slot}: (空)${NC}"
                [ -n "$arrow" ] && echo -ne "  ${CYAN}${arrow}${NC}"
                echo ""
            fi
        done

        echo ""
        echo -e "  ${DIM}─────────────────────────────────${NC}"
        local dst_note=""
        if [ "${normal_has[$((dst_slot-1))]}" = "true" ]; then
            dst_note=" (将覆盖，自动备份)"
        fi
        echo -e "  ${CYAN}计划: 模组槽位${src_slot} → 原版槽位${dst_slot}${dst_note}${NC}"
        echo ""
        echo "    S. 更改来源槽位 (当前: ${src_slot})"
        echo "    D. 更改目标槽位 (当前: ${dst_slot})"
        echo -e "    ${CYAN}Y. 确认执行${NC}"
        echo -e "    ${DIM}0. 取消${NC}"

        read_choice "请选择 [S/D/Y/0]: "
        local choice="$REPLY"

        if [ "$choice" = "0" ]; then write_info "已取消。"; return; fi
        if [ "$choice" = "Y" ] || [ "$choice" = "y" ]; then break; fi

        if [ "$choice" = "S" ] || [ "$choice" = "s" ]; then
            read_choice "选择来源槽位 [1-3]: "
            local pick="$REPLY"
            if [[ "$pick" =~ ^[1-3]$ ]]; then
                if [ "${modded_has[$((pick-1))]}" = "true" ]; then
                    src_slot=$pick
                    write_ok "来源已更改为: 模组槽位${src_slot}"
                else
                    write_warn "模组槽位${pick} 是空的，无法作为来源。"
                fi
            else
                write_warn "请输入 1-3。"
            fi
            continue
        fi

        if [ "$choice" = "D" ] || [ "$choice" = "d" ]; then
            read_choice "选择目标槽位 [1-3]: "
            local pick="$REPLY"
            if [[ "$pick" =~ ^[1-3]$ ]]; then
                dst_slot=$pick
                if [ "${normal_has[$((pick-1))]}" = "true" ]; then
                    write_warn "原版槽位${pick} 已有存档，执行时将自动备份后覆盖。"
                fi
                write_ok "目标已更改为: 原版槽位${dst_slot}"
            else
                write_warn "请输入 1-3。"
            fi
            continue
        fi
    done

    # 执行复制
    local src="${modded_path[$((src_slot-1))]}"
    local dst="${normal_path[$((dst_slot-1))]}"

    echo ""

    # 如果目标有数据，先备份
    if [ "${normal_has[$((dst_slot-1))]}" = "true" ]; then
        write_info "正在备份原版槽位${dst_slot} 的现有存档..."
        do_backup "$steam_id" "normal" "auto_before_copy" "$dst_slot"
        echo ""
    fi

    # 创建目标目录
    mkdir -p "$dst"

    # 复制文件
    local copied=0

    # 复制存档文件
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        local fname
        fname=$(basename "$f")
        local dst_file="${dst}/${fname}"
        [ -f "$dst_file" ] && cp -f "$dst_file" "${dst_file}.before_copy" 2>/dev/null || true
        cp -f "$f" "$dst_file"
        echo -e "    ${GREEN}[√] ${fname}${NC}"
        copied=$((copied + 1))
    done < <(find "$src" -maxdepth 1 -type f 2>/dev/null)

    # 复制子目录 (如 history/)
    while IFS= read -r d; do
        [ -z "$d" ] && continue
        local dname
        dname=$(basename "$d")
        local dst_sub="${dst}/${dname}"
        cp -Rf "$d" "$dst_sub"
        local sub_count
        sub_count=$(find "$d" -type f 2>/dev/null | wc -l | tr -d ' ')
        echo -e "    ${GREEN}[√] ${dname}/ (${sub_count} 个文件)${NC}"
        copied=$((copied + sub_count))
    done < <(find "$src" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)

    echo ""
    if [ "$copied" -gt 0 ]; then
        write_ok "存档复制完成！模组槽位${src_slot} → 原版槽位${dst_slot}（共 ${copied} 个文件）"
        write_info "下次以原版模式进入游戏时，模组进度已同步到原版存档。"
    else
        write_warn "没有文件被复制。"
    fi
}

backup_save() {
    local type="$1"
    echo ""
    local label
    [ "$type" = "normal" ] && label="原版" || label="模组"
    write_info "── 备份${label}存档 ──"
    echo ""

    local steam_id
    if ! steam_id=$(get_steam_id); then return; fi

    # 显示槽位
    local profiles_has=() profiles_time=() profiles_path=()
    local has_any=false
    for i in 1 2 3; do
        local info
        info=$(get_profile_info "$steam_id" "$type" "$i")
        local p_has p_time p_path
        IFS='|' read -r p_has p_time p_path <<< "$info"
        profiles_has+=("$p_has")
        profiles_time+=("$p_time")
        profiles_path+=("$p_path")
        [ "$p_has" = "true" ] && has_any=true
    done

    if ! $has_any; then
        write_info "没有${label}存档可备份。"
        return
    fi

    write_info "${label}存档槽位:"
    echo ""
    for i in 0 1 2; do
        local slot=$((i + 1))
        if [ "${profiles_has[$i]}" = "true" ]; then
            echo -e "    ${WHITE}${slot}. 槽位${slot}: 有存档  ${profiles_time[$i]}${NC}"
        else
            echo -e "    ${DIM}${slot}. 槽位${slot}: (空)${NC}"
        fi
    done
    echo ""
    echo -e "    ${CYAN}A. 备份全部非空槽位${NC}"
    echo -e "    ${DIM}0. 返回${NC}"

    read_choice "请选择 [1-3/A/0]: "
    local choice="$REPLY"
    if [ "$choice" = "0" ]; then return; fi

    if [ "$choice" = "A" ] || [ "$choice" = "a" ]; then
        for i in 0 1 2; do
            if [ "${profiles_has[$i]}" = "true" ]; then
                do_backup "$steam_id" "$type" "manual" "$((i + 1))"
            fi
        done
    else
        if [[ "$choice" =~ ^[1-3]$ ]]; then
            local idx=$((choice - 1))
            if [ "${profiles_has[$idx]}" = "true" ]; then
                do_backup "$steam_id" "$type" "manual" "$choice"
            else
                write_warn "槽位${choice} 是空的，无需备份。"
            fi
        else
            write_err "无效选择。"
        fi
    fi
}

do_backup() {
    local steam_id="$1"
    local type="$2"
    local tag="$3"
    local profile_id="${4:-1}"

    local label
    [ "$type" = "normal" ] && label="原版" || label="模组"

    local src
    if [ "$type" = "normal" ]; then
        src="${SAVE_ROOT}/${steam_id}/profile${profile_id}/saves"
    else
        src="${SAVE_ROOT}/${steam_id}/modded/profile${profile_id}/saves"
    fi

    if [ ! -d "$src" ]; then
        write_err "存档目录不存在: ${src}"
        return
    fi

    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_dir="${SAVE_ROOT}/${steam_id}/backups/${type}_p${profile_id}_${tag}_${timestamp}"
    mkdir -p "$backup_dir"

    local file_count=0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        cp -f "$f" "${backup_dir}/$(basename "$f")"
        file_count=$((file_count + 1))
    done < <(find "$src" -maxdepth 1 -type f -name "*.save*" 2>/dev/null)

    if [ "$file_count" -gt 0 ]; then
        write_ok "${label}槽位${profile_id} 备份完成 (${file_count} 个文件)"
        write_dim "  ${backup_dir}"
    else
        write_warn "没有存档文件可备份。"
        rm -rf "$backup_dir" 2>/dev/null
    fi

    # 清理旧备份：每种类型最多保留 20 份
    local backup_root="${SAVE_ROOT}/${steam_id}/backups"
    if [ -d "$backup_root" ]; then
        local type_backups=()
        while IFS= read -r d; do
            [ -n "$d" ] && type_backups+=("$d")
        done < <(find "$backup_root" -maxdepth 1 -mindepth 1 -type d -name "${type}_*" 2>/dev/null | sort -r)

        if [ ${#type_backups[@]} -gt 20 ]; then
            local to_remove=("${type_backups[@]:20}")
            for old in "${to_remove[@]}"; do
                rm -rf "$old" 2>/dev/null
            done
            write_dim "  已清理 ${#to_remove[@]} 份旧的${label}备份（保留最近 20 份）"
        fi
    fi
}

restore_backup() {
    echo ""
    write_info "── 恢复备份 ──"
    echo ""

    local steam_id
    if ! steam_id=$(get_steam_id); then return; fi

    local backup_root="${SAVE_ROOT}/${steam_id}/backups"
    if [ ! -d "$backup_root" ]; then
        write_info "没有可用的备份。"
        return
    fi

    local backups=()
    while IFS= read -r d; do
        [ -n "$d" ] && backups+=("$d")
    done < <(find "$backup_root" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort -r)

    if [ ${#backups[@]} -eq 0 ]; then
        write_info "没有可用的备份。"
        return
    fi

    write_info "可用备份:"
    echo ""
    for i in "${!backups[@]}"; do
        local bk="${backups[$i]}"
        local bk_name
        bk_name=$(basename "$bk")
        local file_count
        file_count=$(find "$bk" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
        local is_normal=false
        [[ "$bk_name" == normal_* ]] && is_normal=true
        local type_label color
        if $is_normal; then
            type_label="原版"
            color="$GREEN"
        else
            type_label="模组"
            color="$YELLOW"
        fi
        local profile_id=1
        if [[ "$bk_name" =~ _p([0-9])_ ]]; then
            profile_id="${BASH_REMATCH[1]}"
        fi
        echo -e "    ${color}$((i+1)). [${type_label} 槽位${profile_id}] ${bk_name}  (${file_count} 个文件)${NC}"
    done
    echo ""
    echo -e "    ${DIM}0. 返回${NC}"
    read_choice "请选择要恢复的备份 [编号/0]: "
    local choice="$REPLY"

    if [ "$choice" = "0" ]; then return; fi
    local idx=$((choice - 1))
    if [ "$idx" -lt 0 ] || [ "$idx" -ge ${#backups[@]} ]; then
        write_err "无效选择。"
        return
    fi

    local selected="${backups[$idx]}"
    local selected_name
    selected_name=$(basename "$selected")
    local is_normal=false
    [[ "$selected_name" == normal_* ]] && is_normal=true

    local profile_id=1
    if [[ "$selected_name" =~ _p([0-9])_ ]]; then
        profile_id="${BASH_REMATCH[1]}"
    fi

    local type_label restore_to current_type
    if $is_normal; then
        type_label="原版"
        current_type="normal"
        restore_to="${SAVE_ROOT}/${steam_id}/profile${profile_id}/saves"
    else
        type_label="模组"
        current_type="modded"
        restore_to="${SAVE_ROOT}/${steam_id}/modded/profile${profile_id}/saves"
    fi

    echo ""
    write_info "将恢复到: ${type_label}槽位${profile_id}"
    write_dim "  ${restore_to}"
    echo ""

    # 允许更改目标槽位
    read_choice "恢复到其他槽位？输入槽位号 [1-3] 或直接回车使用槽位${profile_id}: "
    if [[ "$REPLY" =~ ^[1-3]$ ]]; then
        profile_id="$REPLY"
        if $is_normal; then
            restore_to="${SAVE_ROOT}/${steam_id}/profile${profile_id}/saves"
        else
            restore_to="${SAVE_ROOT}/${steam_id}/modded/profile${profile_id}/saves"
        fi
        write_ok "已更改为: ${type_label}槽位${profile_id}"
    fi

    read_choice "确认恢复？输入 Y 确认: "
    if [ "$REPLY" != "Y" ] && [ "$REPLY" != "y" ]; then
        write_info "已取消。"
        return
    fi

    # 恢复前备份当前存档
    if [ -f "${restore_to}/progress.save" ]; then
        write_info "正在备份当前${type_label}槽位${profile_id}..."
        do_backup "$steam_id" "$current_type" "auto_before_restore" "$profile_id"
    fi

    # 执行恢复
    mkdir -p "$restore_to"

    local restored=0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        cp -f "$f" "${restore_to}/$(basename "$f")"
        restored=$((restored + 1))
    done < <(find "$selected" -maxdepth 1 -type f 2>/dev/null)

    echo ""
    write_ok "恢复完成！共恢复 ${restored} 个文件到${type_label}槽位${profile_id}。"
}

# ============================================================
#  功能: 设置
# ============================================================
show_settings() {
    while true; do
        clear
        write_title "设置"

        local dir
        write_info "当前游戏目录:"
        if dir=$(get_game_dir); then
            echo -e "    ${GREEN}${dir}${NC}"
            echo -e "    ${DIM}模组目录: $(get_mods_dir "$dir")${NC}"
        else
            write_dim "    (未设置)"
        fi
        echo ""
        echo "    1. 自动检测游戏目录"
        echo "    2. 手动设置游戏目录"
        echo "    3. 清除配置文件"
        echo "    4. 清理模组备份文件 (.bak)"
        echo -e "    ${DIM}0. 返回主菜单${NC}"

        read_choice "请选择 [0-4]: "
        case "$REPLY" in
            1)
                echo ""
                write_info "正在自动检测..."
                local found
                if found=$(find_game_dir); then
                    write_ok "检测成功: ${found}"
                    GAME_DIR="$found"
                    save_config
                else
                    write_err "自动检测失败。请尝试手动设置。"
                fi
                pause_and_return
                ;;
            2)
                set_game_dir_manual || true
                pause_and_return
                ;;
            3)
                if [ -f "$CONFIG_FILE" ]; then
                    rm -f "$CONFIG_FILE"
                    GAME_DIR=""
                    write_ok "配置已清除。"
                else
                    write_info "没有配置文件需要清除。"
                fi
                pause_and_return
                ;;
            4)
                local dir
                if ! dir=$(get_game_dir); then
                    write_err "请先设置游戏目录。"
                    pause_and_return
                    continue
                fi
                local mods_dir
                mods_dir=$(get_mods_dir "$dir")
                local bak_files=()
                while IFS= read -r f; do
                    [ -n "$f" ] && bak_files+=("$f")
                done < <(find "$mods_dir" -type f -name "*.bak*" 2>/dev/null)

                if [ ${#bak_files[@]} -gt 0 ]; then
                    write_info "找到 ${#bak_files[@]} 个备份文件:"
                    for f in "${bak_files[@]}"; do
                        write_dim "  ${f}"
                    done
                    read_choice "删除全部？输入 Y 确认: "
                    if [ "$REPLY" = "Y" ] || [ "$REPLY" = "y" ]; then
                        for f in "${bak_files[@]}"; do
                            rm -f "$f" 2>/dev/null
                        done
                        write_ok "已清理 ${#bak_files[@]} 个备份文件。"
                    fi
                else
                    write_info "没有备份文件需要清理。"
                fi
                pause_and_return
                ;;
            0) return ;;
        esac
    done
}

# ============================================================
#  在线更新
# ============================================================

# ── HTTP 请求（带重试） ──
invoke_with_retry() {
    local url="$1"
    local timeout="${2:-8}"
    local max_retries="${3:-2}"
    local attempt=0

    while true; do
        local result
        result=$(curl -s -A "STS2ModManager/$VERSION" --connect-timeout "$timeout" -m $((timeout * 2)) "$url" 2>/dev/null) && {
            echo "$result"
            return 0
        }
        attempt=$((attempt + 1))
        if [ "$attempt" -gt "$max_retries" ]; then
            return 1
        fi
        write_dim "    请求超时，重试中 ($attempt/$max_retries)..." >&2
        sleep 0.8
    done
}

# ── 检查在线更新 ──
check_online_update() {
    if [ "$HAS_PYTHON3" != "true" ]; then return 1; fi
    local game_dir="$1"
    local mods_dir
    mods_dir=$(get_mods_dir "$game_dir")

    python3 - "$UPDATE_API" "$VERSION" "$mods_dir" "$LAST_CHECK_FILE" << 'PYEOF'
import json, sys, os, urllib.request, datetime

api = sys.argv[1]
version = sys.argv[2]
mods_dir = sys.argv[3]
out_file = sys.argv[4]

result = {"error": None, "updates": [], "up_to_date": [], "check_time": ""}

try:
    req = urllib.request.Request(f"{api}/check",
        headers={"User-Agent": f"STS2ModManager/{version}"})
    with urllib.request.urlopen(req, timeout=8) as resp:
        data = json.loads(resp.read().decode("utf-8"))
except Exception as e:
    msg = str(e)[:40]
    result["error"] = msg
    result["check_time"] = datetime.datetime.now().strftime("%m-%d %H:%M")
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False)
    sys.exit(0)

mods = data.get("mods", {})

def find_live_manifest(mod_dir):
    try:
        names = sorted(os.listdir(mod_dir))
    except Exception:
        return None, None
    for name in names:
        if not name.endswith(".json") or name == "mod_manifest.json":
            continue
        path = os.path.join(mod_dir, name)
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            continue
        if isinstance(data, dict) and data.get("id"):
            return path, data
    return None, None

def load_manifest_info(mod_dir):
    live_path, live = find_live_manifest(mod_dir)
    legacy_path = os.path.join(mod_dir, "mod_manifest.json")
    legacy = None
    if os.path.isfile(legacy_path):
        try:
            with open(legacy_path, encoding="utf-8") as f:
                legacy = json.load(f)
        except Exception:
            legacy = None

    if live:
        mod_id = str(live.get("id") or os.path.basename(mod_dir))
        return {
            "id": mod_id,
            "name": live.get("name") or (legacy.get("name") if legacy else mod_id),
            "version": live.get("version") or (legacy.get("version") if legacy else ""),
        }

    if legacy:
        mod_id = str(legacy.get("pck_name") or os.path.basename(mod_dir))
        return {
            "id": mod_id,
            "name": legacy.get("name") or mod_id,
            "version": legacy.get("version") or "",
        }

    return None

if os.path.isdir(mods_dir):
    for d in os.listdir(mods_dir):
        info = load_manifest_info(os.path.join(mods_dir, d))
        if not info:
            continue
        pck_name = info["id"]
        local_ver = info["version"]
        if not pck_name or not local_ver or pck_name not in mods:
            continue
        remote = mods[pck_name]
        remote_ver = remote.get("latest", "")
        if not remote_ver:
            continue
        entry = {
            "name": pck_name,
            "local_name": info["name"],
            "cloud_name": remote.get("name", pck_name),
            "local_ver": local_ver,
            "remote_ver": remote_ver,
            "changelog": remote.get("changelog", ""),
            "changelog_detail": remote.get("changelog_detail", []),
            "updated_at": remote.get("updated_at", ""),
            "install_dir": os.path.join(mods_dir, d)
        }
        needs_update = False
        try:
            from packaging.version import Version
            needs_update = Version(remote_ver) > Version(local_ver)
        except Exception:
            # Fallback: tuple comparison
            try:
                rv = tuple(int(x) for x in remote_ver.split("."))
                lv = tuple(int(x) for x in local_ver.split("."))
                needs_update = rv > lv
            except Exception:
                needs_update = remote_ver != local_ver
        if needs_update:
            result["updates"].append(entry)
        else:
            result["up_to_date"].append(entry)

result["check_time"] = datetime.datetime.now().strftime("%m-%d %H:%M")
with open(out_file, "w", encoding="utf-8") as f:
    json.dump(result, f, ensure_ascii=False)
PYEOF

    if [ ! -f "$LAST_CHECK_FILE" ]; then
        echo '{"error":"python3 failed","updates":[],"up_to_date":[],"check_time":""}' > "$LAST_CHECK_FILE"
    fi
    LAST_CHECK_UPDATES_COUNT=$(python3 -c "
import json
with open('$LAST_CHECK_FILE') as f:
    d = json.load(f)
print(len(d.get('updates', [])))
" 2>/dev/null) || LAST_CHECK_UPDATES_COUNT=0
}

# ── 更新单个模组 ──
update_single_mod() {
    if [ "$HAS_PYTHON3" != "true" ]; then return 1; fi
    local mod_name="$1"
    local display_name="$2"
    local remote_ver="$3"
    local local_ver="$4"
    local install_dir="$5"

    write_info "[$display_name] 获取下载链接..."
    local resp
    resp=$(invoke_with_retry "$UPDATE_API/download?mod=$mod_name") || {
        write_err "[$display_name] 获取下载链接失败（网络超时）"
        return 1
    }

    local url
    url=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(d.get('url', ''))
except:
    print('')
" <<< "$resp" 2>/dev/null)

    if [ -z "$url" ]; then
        write_err "[$display_name] 下载链接无效"
        return 1
    fi

    local temp_zip="/tmp/sts2_update_${mod_name}.zip"
    local temp_extract="/tmp/sts2_extract_${mod_name}"

    write_info "[$display_name] 下载 v${remote_ver}..."
    if ! curl -s -A "STS2ModManager/$VERSION" -L -o "$temp_zip" --connect-timeout 15 -m 120 "$url"; then
        write_err "[$display_name] 下载失败: 网络超时或链接已过期"
        rm -f "$temp_zip"
        return 1
    fi

    local size
    size=$(du -k "$temp_zip" 2>/dev/null | cut -f1)
    write_dim "    下载完成 (${size}KB)"

    write_info "[$display_name] 安装中..."
    rm -rf "$temp_extract"
    mkdir -p "$temp_extract"
    if ! unzip -q -o "$temp_zip" -d "$temp_extract" 2>/dev/null; then
        write_err "[$display_name] 解压失败"
        rm -f "$temp_zip"
        rm -rf "$temp_extract"
        return 1
    fi

    # 找到包含 DLL 文件的目录
    local source_dir
    source_dir=$(find "$temp_extract" -name "*.dll" -print -quit 2>/dev/null | xargs dirname 2>/dev/null)
    if [ -z "$source_dir" ]; then
        write_err "[$display_name] zip 中未找到 DLL 文件"
        rm -f "$temp_zip"
        rm -rf "$temp_extract"
        return 1
    fi

    cp -f "$source_dir"/* "$install_dir/" 2>/dev/null

    # 同步更新分发包 Mods/ 目录
    if [ -d "$MODS_SOURCE" ]; then
        local local_mod_dir="$MODS_SOURCE/$mod_name"
        if [ -d "$local_mod_dir" ]; then
            # 清理旧版本号目录
            find "$MODS_SOURCE" -maxdepth 1 -type d -name "${mod_name}_v*" -exec rm -rf {} + 2>/dev/null
            cp -f "$source_dir"/* "$local_mod_dir/" 2>/dev/null
            write_dim "    分发包已同步"
        else
            # 按版本号目录查找（如 SpeedX_v0.6.0）
            local versioned_dir
            versioned_dir=$(find "$MODS_SOURCE" -maxdepth 1 -type d -name "${mod_name}_v*" 2>/dev/null | head -1)
            if [ -n "$versioned_dir" ]; then
                local new_dir="$MODS_SOURCE/${mod_name}_v${remote_ver}"
                rm -rf "$versioned_dir"
                mkdir -p "$new_dir"
                cp -f "$source_dir"/* "$new_dir/" 2>/dev/null
                write_dim "    分发包已同步"
            fi
        fi
    fi

    write_ok "[$display_name] v${local_ver} -> v${remote_ver} 更新成功"

    rm -f "$temp_zip"
    rm -rf "$temp_extract"
    return 0
}

# ── 模组详情（完整更新日志） ──
show_mod_details() {
    if [ ! -f "$LAST_CHECK_FILE" ]; then return; fi

    python3 - "$LAST_CHECK_FILE" << 'PYEOF'
import json, sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

all_mods = data.get("up_to_date", []) + data.get("updates", [])
if not all_mods:
    print("  \033[2m无模组数据\033[0m", file=sys.stderr)
    sys.exit(0)

print("", file=sys.stderr)
print("  \033[0;36m── 模组详情 ──\033[0m", file=sys.stderr)
print("", file=sys.stderr)

updates_names = {m["name"] for m in data.get("updates", [])}

for m in all_mods:
    is_update = m["name"] in updates_names
    name_color = "\033[1;33m" if is_update else "\033[0;32m"
    nc = "\033[0m"
    dim = "\033[2m"
    cyan = "\033[0;36m"
    white = "\033[1;37m"
    green = "\033[0;32m"

    print(f"  {name_color}{m['cloud_name']}{nc}", file=sys.stderr)
    if m.get("local_name") and m["local_name"] != m["cloud_name"]:
        print(f"  {dim}  本地名称:  {m['local_name']}{nc}", file=sys.stderr)
    print(f"  {dim}  本地版本:  {nc}{white}v{m['local_ver']}{nc}", file=sys.stderr)
    ver_color = green if is_update else white
    print(f"  {dim}  云端版本:  {nc}{ver_color}v{m['remote_ver']}{nc}", file=sys.stderr)
    if m.get("updated_at"):
        print(f"  {dim}  发布日期:  {m['updated_at']}{nc}", file=sys.stderr)
    detail = m.get("changelog_detail", [])
    if detail:
        print(f"  {dim}  更新日志:{nc}", file=sys.stderr)
        for line in detail:
            print(f"  {cyan}    - {line}{nc}", file=sys.stderr)
    elif m.get("changelog"):
        print(f"  {dim}  更新日志:  {nc}{cyan}{m['changelog']}{nc}", file=sys.stderr)
    print("", file=sys.stderr)
PYEOF
}

# ── 显示更新面板 ──
show_update_panel() {
    local is_startup="${1:-false}"

    if [ ! -f "$LAST_CHECK_FILE" ]; then return; fi

    # 用 python3 渲染表格部分
    local panel_output
    panel_output=$(python3 - "$LAST_CHECK_FILE" "$is_startup" << 'PYEOF'
import json, sys

check_file = sys.argv[1]
is_startup = sys.argv[2] == "true"

with open(check_file, encoding="utf-8") as f:
    data = json.load(f)

NC = "\033[0m"
RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
CYAN = "\033[0;36m"
WHITE = "\033[1;37m"
DIM = "\033[2m"

check_time = data.get("check_time", "")
error = data.get("error")
updates = data.get("updates", [])
up_to_date = data.get("up_to_date", [])
all_mods = up_to_date + updates

def display_width(text):
    w = 0
    for c in text:
        w += 2 if ord(c) > 0x7F else 1
    return w

def truncate(text, max_w):
    w = 0
    for i, c in enumerate(text):
        cw = 2 if ord(c) > 0x7F else 1
        if w + cw > max_w:
            return text[:i]
        w += cw
    return text

def pad(text, target_w):
    return text + " " * max(0, target_w - display_width(text))

print("")
print(f"  {CYAN}── 模组更新检查 ──{NC}{DIM}                          {check_time}{NC}")
print("")

if error:
    print(f"  {YELLOW}[!] 连接更新服务器失败: {error}{NC}")
    # Signal: error
    print(f"__SIGNAL__:error")
    sys.exit(0)

if not all_mods:
    print(f"  {DIM}未检测到已安装的皮皮模组{NC}")
    # Signal: empty
    print(f"__SIGNAL__:empty")
    sys.exit(0)

# Dynamic column width
name_col = 20
for m in all_mods:
    w = display_width(m["cloud_name"])
    if w + 2 > name_col:
        name_col = w + 2
if name_col > 28:
    name_col = 28

# Header
header = f"    {pad('模组', name_col)}  {pad('本地版本', 10)}  {pad('云端版本', 10)}  更新说明"
print(f"{DIM}{header}{NC}")
sep = "─" * name_col + "  " + "─" * 10 + "  " + "─" * 10 + "  " + "─" * 16
print(f"    {DIM}{sep}{NC}")

# Up-to-date mods
for m in up_to_date:
    name = m["cloud_name"]
    if display_width(name) > name_col:
        name = truncate(name, name_col - 2) + ".."
    log = m.get("changelog", "")
    if m.get("updated_at"):
        log = f"{log} ({m['updated_at']})" if log else m["updated_at"]
    if display_width(log) > 24:
        log = truncate(log, 22) + ".."
    mark = f"{GREEN}[√] {NC}"
    print(f"  {mark}{DIM}{pad(name, name_col - 4)}    {pad('v' + m['local_ver'], 10)}  {pad('v' + m['remote_ver'], 10)}  {log}{NC}")

# Updatable mods
for i, m in enumerate(updates):
    idx_str = f"{i+1}. "
    name = m["cloud_name"]
    idx_width = len(idx_str)
    avail_width = name_col - idx_width
    if display_width(name) > avail_width:
        name = truncate(name, avail_width - 2) + ".."
    log = m.get("changelog", "")
    if m.get("updated_at"):
        log = f"{log} ({m['updated_at']})" if log else m["updated_at"]
    if display_width(log) > 24:
        log = truncate(log, 22) + ".."
    local_ver_str = pad("v" + m["local_ver"], 10)
    remote_ver_str = pad("v" + m["remote_ver"], 10)
    print(f"  {YELLOW}{idx_str}{NC}{WHITE}{pad(name, avail_width)}{NC}    {DIM}{local_ver_str}{NC}  {GREEN}{remote_ver_str}{NC}  {CYAN}{log}{NC}")

print("")

update_count = len(updates)
if update_count == 0:
    print(f"  {GREEN}[√] 所有模组已是最新版本{NC}")
    print("")
    # Signal: no_updates
    print(f"__SIGNAL__:no_updates")
else:
    print(f"  {YELLOW}[↑] 发现 {update_count} 个模组可更新{NC}")
    print("")
    if update_count == 1:
        print(f"__SIGNAL__:has_updates:1")
    else:
        print(f"__SIGNAL__:has_updates:{update_count}")
PYEOF
    ) 2>/dev/null

    if [ -z "$panel_output" ]; then
        write_warn "更新面板渲染失败"
        if [ "$is_startup" != "true" ]; then pause_and_return; fi
        return
    fi

    # Print all lines except signal lines to stderr
    local signal_line=""
    while IFS= read -r line; do
        if [[ "$line" == __SIGNAL__:* ]]; then
            signal_line="$line"
        else
            echo -e "$line" >&2
        fi
    done <<< "$panel_output"

    # Handle signals
    local signal_type="${signal_line#__SIGNAL__:}"

    case "$signal_type" in
        error)
            if [ "$is_startup" != "true" ]; then pause_and_return; fi
            ;;
        empty)
            if [ "$is_startup" != "true" ]; then pause_and_return; fi
            ;;
        no_updates)
            read_choice "按 D=查看详情 / Enter=继续: "
            if [ "$REPLY" = "D" ] || [ "$REPLY" = "d" ]; then
                show_mod_details
                pause_and_return
            fi
            ;;
        has_updates:*)
            local update_count="${signal_type#has_updates:}"
            local prompt
            if [ "$update_count" -eq 1 ]; then
                prompt="按 1=更新 / D=详情 / Enter=跳过: "
            else
                prompt="按 A=全部更新 / 1-${update_count}=选择 / D=详情 / Enter=跳过: "
            fi
            read_choice "$prompt"
            local choice="$REPLY"

            if [ -z "$choice" ] || [ "$choice" = "0" ]; then
                return
            fi

            if [ "$choice" = "D" ] || [ "$choice" = "d" ]; then
                show_mod_details
                pause_and_return
                return
            fi

            if [ "$choice" = "A" ] || [ "$choice" = "a" ]; then
                echo "" >&2
                local success=0
                local failed=0
                # Read updates from check file and process each
                local update_items
                update_items=$(python3 -c "
import json
with open('$LAST_CHECK_FILE') as f:
    d = json.load(f)
for u in d.get('updates', []):
    # tab-separated: name, cloud_name, remote_ver, local_ver, install_dir
    print(u['name'] + '\t' + u['cloud_name'] + '\t' + u['remote_ver'] + '\t' + u['local_ver'] + '\t' + u['install_dir'])
" 2>/dev/null)

                while IFS=$'\t' read -r u_name u_display u_remote u_local u_dir; do
                    [ -z "$u_name" ] && continue
                    if update_single_mod "$u_name" "$u_display" "$u_remote" "$u_local" "$u_dir"; then
                        success=$((success + 1))
                        # Move from updates to up_to_date in check file
                        python3 -c "
import json
with open('$LAST_CHECK_FILE') as f:
    d = json.load(f)
d['updates'] = [u for u in d.get('updates', []) if u['name'] != '$u_name']
for u in d.get('up_to_date', []):
    pass  # keep existing
# find the updated entry and move it
for u in list(d.get('updates', [])):
    if u['name'] == '$u_name':
        u['local_ver'] = u['remote_ver']
        d['up_to_date'].append(u)
        break
with open('$LAST_CHECK_FILE', 'w') as f:
    json.dump(d, f, ensure_ascii=False)
" 2>/dev/null
                    else
                        failed=$((failed + 1))
                    fi
                done <<< "$update_items"

                echo "" >&2
                if [ "$failed" -eq 0 ]; then
                    write_ok "全部更新完成 ($success 个模组)"
                else
                    write_warn "更新完成: $success 成功, $failed 失败"
                fi
                # Refresh count
                LAST_CHECK_UPDATES_COUNT=$(python3 -c "
import json
with open('$LAST_CHECK_FILE') as f:
    d = json.load(f)
print(len(d.get('updates', [])))
" 2>/dev/null) || LAST_CHECK_UPDATES_COUNT=0
                pause_and_return
            else
                # Single number selection
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$update_count" ]; then
                    echo "" >&2
                    local idx=$((choice - 1))
                    local u_info
                    u_info=$(python3 -c "
import json
with open('$LAST_CHECK_FILE') as f:
    d = json.load(f)
u = d['updates'][$idx]
print(u['name'] + '\t' + u['cloud_name'] + '\t' + u['remote_ver'] + '\t' + u['local_ver'] + '\t' + u['install_dir'])
" 2>/dev/null)
                    local u_name u_display u_remote u_local u_dir
                    IFS=$'\t' read -r u_name u_display u_remote u_local u_dir <<< "$u_info"
                    if [ -n "$u_name" ]; then
                        if update_single_mod "$u_name" "$u_display" "$u_remote" "$u_local" "$u_dir"; then
                            # Update check file
                            python3 -c "
import json
with open('$LAST_CHECK_FILE') as f:
    d = json.load(f)
updated = None
d_updates = d.get('updates', [])
for i, u in enumerate(d_updates):
    if u['name'] == '$u_name':
        updated = u.copy()
        updated['local_ver'] = updated['remote_ver']
        d_updates.pop(i)
        break
d['updates'] = d_updates
if updated:
    d.setdefault('up_to_date', []).append(updated)
with open('$LAST_CHECK_FILE', 'w') as f:
    json.dump(d, f, ensure_ascii=False)
" 2>/dev/null
                        fi
                        # Refresh count
                        LAST_CHECK_UPDATES_COUNT=$(python3 -c "
import json
with open('$LAST_CHECK_FILE') as f:
    d = json.load(f)
print(len(d.get('updates', [])))
" 2>/dev/null) || LAST_CHECK_UPDATES_COUNT=0
                    fi
                    pause_and_return
                fi
            fi
            ;;
    esac
}

# ── 静默同步分发包 Mods/ 与游戏目录 ──
sync_local_mods() {
    local game_dir="$1"
    local mods_dir
    mods_dir=$(get_mods_dir "$game_dir")
    [ ! -d "$mods_dir" ] && return
    [ ! -d "$MODS_SOURCE" ] && return

python3 - "$mods_dir" "$MODS_SOURCE" << 'PYEOF'
import json, os, sys, shutil

mods_dir = sys.argv[1]
mods_source = sys.argv[2]

def find_live_manifest(mod_dir):
    try:
        names = sorted(os.listdir(mod_dir))
    except Exception:
        return None, None
    for name in names:
        if not name.endswith(".json") or name == "mod_manifest.json":
            continue
        path = os.path.join(mod_dir, name)
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            continue
        if isinstance(data, dict) and data.get("id"):
            return path, data
    return None, None

def load_manifest_info(mod_dir, preferred_name=None):
    live_path, live = find_live_manifest(mod_dir)
    legacy_path = os.path.join(mod_dir, "mod_manifest.json")
    legacy = None
    if os.path.isfile(legacy_path):
        try:
            with open(legacy_path, encoding="utf-8") as f:
                legacy = json.load(f)
        except Exception:
            legacy = None

    if live:
        mod_id = str(live.get("id") or preferred_name or os.path.basename(mod_dir))
        return {
            "id": mod_id,
            "version": live.get("version") or (legacy.get("version") if legacy else ""),
        }

    if legacy:
        mod_id = str(legacy.get("pck_name") or preferred_name or os.path.basename(mod_dir))
        return {
            "id": mod_id,
            "version": legacy.get("version") or "",
        }

    return None

for d in os.listdir(mods_dir):

    info = load_manifest_info(os.path.join(mods_dir, d), preferred_name=d)
    if not info:
        continue
    pck = info["id"]
    installed_ver = info["version"]
    if not pck or not installed_ver:
        continue

    # Find matching local distribution directory
    local_dir = None
    local_ver = None
    for ld in os.listdir(mods_source):
        ld_path = os.path.join(mods_source, ld)
        if not os.path.isdir(ld_path):
            continue
        if ld == pck or ld.startswith(f"{pck}_v"):
            local_info = load_manifest_info(ld_path, preferred_name=pck)
            if local_info and local_info["id"] == pck:
                local_dir = ld_path
                local_ver = local_info["version"]
                break
    if not local_dir or not local_ver:
        continue

    # Compare versions: installed > local -> sync
    try:
        iv = tuple(int(x) for x in installed_ver.split("."))
        lv = tuple(int(x) for x in local_ver.split("."))
        if iv > lv:
            new_dir = os.path.join(mods_source, f"{pck}_v{installed_ver}")
            shutil.rmtree(local_dir, ignore_errors=True)
            os.makedirs(new_dir, exist_ok=True)
            src = os.path.join(mods_dir, d)
            for item in os.listdir(src):
                s = os.path.join(src, item)
                t = os.path.join(new_dir, item)
                if os.path.isfile(s):
                    shutil.copy2(s, t)
    except Exception:
        pass
PYEOF
}

# ============================================================
#  主菜单
# ============================================================
show_main_menu() {
    load_config

    # 启动时自动检测游戏目录 + 检查在线更新
    local startup_dir
    if startup_dir=$(ensure_game_dir 2>/dev/null) && [ -n "$startup_dir" ]; then
        if [ "$HAS_PYTHON3" = "true" ]; then
            write_dim "正在检查模组更新..." >&2
            check_online_update "$startup_dir" 2>/dev/null || true

            # 静默同步分发包
            sync_local_mods "$startup_dir" 2>/dev/null || true
        fi

        # 启动时自动展示模组状态（需要 python3）
        if [ "$HAS_PYTHON3" = "true" ]; then
            clear
            show_update_panel true
        fi
    fi

    while true; do
        clear
        echo ""
        echo -e "  ${CYAN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "  ${CYAN}║   杀戮尖塔2 模组管理器 v${VERSION}              ║${NC}"
        echo -e "  ${CYAN}║   Slay the Spire 2 Mod Manager (macOS)      ║${NC}"
        echo -e "  ${CYAN}╚══════════════════════════════════════════════╝${NC}"
        echo -ne "  ${DIM}皮一下就很凡@Bilibili${NC}"
        echo -e "  ${CYAN}space.bilibili.com/26786884${NC}"
        echo ""

        local dir
        if dir=$(get_game_dir); then
            echo -e "  ${GREEN}[√] 游戏目录: ${dir}${NC}"
        else
            echo -e "  ${YELLOW}[?] 游戏目录: 未设置${NC}"
        fi

        # 快速统计
        if [ -n "$GAME_DIR" ] && [ -d "${GAME_DIR}/${STS2_APP}" ]; then
            local inst_count=0 avail_count=0
            while IFS= read -r _; do inst_count=$((inst_count + 1)); done < <(get_installed_mods "$GAME_DIR")
            while IFS= read -r _; do avail_count=$((avail_count + 1)); done < <(get_available_mods)
            write_dim "      已安装 ${inst_count} 个模组 | 可安装 ${avail_count} 个模组"
        fi

        # 更新状态摘要
        if [ -f "$LAST_CHECK_FILE" ]; then
            local check_error
            check_error=$(python3 -c "
import json
with open('$LAST_CHECK_FILE') as f:
    d = json.load(f)
print(d.get('error', '') or '')
" 2>/dev/null)
            if [ -n "$check_error" ]; then
                write_dim "      在线更新: 检查失败"
            elif [ "$LAST_CHECK_UPDATES_COUNT" -gt 0 ]; then
                echo "" >&2
                echo -e "  ${YELLOW}[↑] ${LAST_CHECK_UPDATES_COUNT} 个模组可更新 (选 6 查看详情)${NC}" >&2
            else
                local total_tracked
                total_tracked=$(python3 -c "
import json
with open('$LAST_CHECK_FILE') as f:
    d = json.load(f)
print(len(d.get('updates', [])) + len(d.get('up_to_date', [])))
" 2>/dev/null) || total_tracked=0
                if [ "$total_tracked" -gt 0 ]; then
                    local check_time
                    check_time=$(python3 -c "
import json
with open('$LAST_CHECK_FILE') as f:
    d = json.load(f)
print(d.get('check_time', ''))
" 2>/dev/null)
                    echo -ne "  ${GREEN}[√] 模组已是最新${NC}" >&2
                    write_dim "  $check_time"
                fi
            fi
        fi

        echo ""
        echo -e "    ${CYAN}1. 安装模组${NC}"
        echo "    2. 卸载模组"
        echo "    3. 查看已安装模组"
        echo "    4. 存档管理"
        echo "    5. 设置"
        if [ "$LAST_CHECK_UPDATES_COUNT" -gt 0 ]; then
            echo -e "    ${YELLOW}6. 在线更新模组 (${LAST_CHECK_UPDATES_COUNT})${NC}"
        else
            echo "    6. 检查在线更新"
        fi
        echo -e "    ${DIM}0. 退出${NC}"

        read_choice "请选择 [0-6]: "
        case "$REPLY" in
            1) install_mod ;;
            2) uninstall_mod ;;
            3) show_installed_mods ;;
            4) show_save_menu ;;
            5) show_settings ;;
            6)
                if [ -n "$GAME_DIR" ] && [ -d "${GAME_DIR}/${STS2_APP}" ]; then
                    write_dim "正在检查模组更新..." >&2
                    check_online_update "$GAME_DIR" 2>/dev/null || true
                    show_update_panel false
                else
                    write_err "请先设置游戏目录"
                    pause_and_return
                fi
                ;;
            0)
                echo ""
                write_info "再见！祝你在尖塔中好运 :)"
                echo ""
                exit 0
                ;;
        esac
    done
}

# ── 启动 ──
start_logging
show_main_menu
