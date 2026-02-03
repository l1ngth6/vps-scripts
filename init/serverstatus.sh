#!/usr/bin/env bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pause() {
  read -r -p "按回车继续..." _
}

download_status_script() {
  cd "$script_dir" || exit 1
  wget --no-check-certificate -qO status.sh \
    'https://raw.githubusercontent.com/zdz/ServerStatus-Rust/master/scripts/status.sh'
  chmod +x status.sh
}

status_menu() {
  while true; do
    clear
    cat <<'EOF'
探针相关
1) 安装 服务端
2) 安装 客户端（可选卸载）
3) 卸载 客户端
0) 返回
EOF
    read -r -p "请选择: " status_choice
    case "$status_choice" in
      1)
        download_status_script
        (cd "$script_dir" && bash status.sh -i -s)
        pause
        ;;
      2)
        download_status_script
        read -r -p "是否先卸载已有客户端？[y/N]: " uninstall_first
        if [[ "$uninstall_first" =~ ^[Yy]$ ]]; then
          (cd "$script_dir" && bash status.sh -un -c)
        fi
        (cd "$script_dir" && bash status.sh -i -c)
        pause
        ;;
      3)
        download_status_script
        (cd "$script_dir" && bash status.sh -un -c)
        pause
        ;;
      0)
        break
        ;;
      *)
        echo "无效选择"
        pause
        ;;
    esac
  done
}

status_menu
