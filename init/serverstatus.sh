#!/usr/bin/env bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pause() {
  read -r -p "按回车继续..." _
}

download_status_script() {
  if ! command -v wget >/dev/null 2>&1; then
    echo "缺少 wget，请先安装 wget 和 ca-certificates。"
    return 1
  fi
  if ! wget -T 30 -t 2 -qO "$1" \
    'https://raw.githubusercontent.com/zdz/ServerStatus-Rust/master/scripts/status.sh' \
    || [[ ! -s "$1" ]] || ! bash -n "$1"; then
    echo "下载失败或脚本无效，已取消；请检查网络及 ca-certificates。"
    return 1
  fi
}

status_menu() (
  if [[ -f /etc/alpine-release ]]; then
    echo "Alpine 暂不支持探针安装和卸载，上游安装脚本依赖 systemd。"
    return 0
  fi
  local status_script status_choice uninstall_first
  status_script="$(mktemp /tmp/serverstatus.XXXXXX)" || return 1
  trap 'rm -f "$status_script"' EXIT
  cd "$script_dir" || return 1
  while true; do
    clear
    cat <<'EOF'
探针相关
1) 安装 服务端
2) 安装 客户端（可选卸载）
3) 卸载 客户端
0) 返回
EOF
    read -r -p "请选择: " status_choice || return 0
    case "$status_choice" in
      1)
        download_status_script "$status_script" && bash "$status_script" -i -s
        pause || return 0
        ;;
      2)
        if download_status_script "$status_script"; then
          read -r -p "是否先卸载已有客户端？[y/N]: " uninstall_first || return 0
          if [[ "$uninstall_first" =~ ^[Yy]$ ]]; then
            if ! bash "$status_script" -un -c; then
              echo "客户端卸载失败，已取消后续安装。"
              pause || return 0
              continue
            fi
          fi
          bash "$status_script" -i -c
        fi
        pause || return 0
        ;;
      3)
        download_status_script "$status_script" && bash "$status_script" -un -c
        pause || return 0
        ;;
      0)
        break
        ;;
      *)
        echo "无效选择"
        pause || return 0
        ;;
    esac
  done
)

status_menu
