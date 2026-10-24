#!/usr/bin/env bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_base_url="https://raw.githubusercontent.com/l1ngth6/vps-scripts/main/init"

pause() {
  read -r -p "按回车继续..." _
}

remove_bbr_lotserver() {
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q "^lotserver"; then
    systemctl stop lotserver >/dev/null 2>&1 || true
    systemctl disable lotserver >/dev/null 2>&1 || true
  fi
}

bbrfq() {
  local current_qdisc
  local current_congestion_control
  local available_congestion_control
  local sysctl_file="/etc/sysctl.d/99-vps-scripts-bbr.conf"
  local applied=true

  if [[ $EUID -ne 0 ]]; then
    echo "需要 root 权限来修改 BBR 配置。"
    return 1
  fi
  if ! command -v sysctl >/dev/null 2>&1; then
    echo "缺少 sysctl，请先安装 procps（Debian）或检查 BusyBox（Alpine）。"
    return 1
  fi

  mkdir -p /etc/sysctl.d || return 1
  printf '%s\n' 'net.core.default_qdisc=fq' 'net.ipv4.tcp_congestion_control=bbr' \
    > "$sysctl_file" || return 1
  remove_bbr_lotserver
  sysctl -p "$sysctl_file" || applied=false

  current_qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
  current_congestion_control="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
  available_congestion_control="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"

  if [[ "$applied" == true && "$current_qdisc" == "fq" && "$current_congestion_control" == "bbr" ]]; then
    echo "BBR和FQ默认队列配置已在当前运行内核中加载，无需重启。"
    echo "后续新建的TCP连接将使用BBR；已有连接和队列规则不会被强制切换。"
    return
  fi

  echo "配置已保存，但未能在当前运行内核中完全生效："
  echo "  net.core.default_qdisc=${current_qdisc:-读取失败}（期望值：fq）"
  echo "  net.ipv4.tcp_congestion_control=${current_congestion_control:-读取失败}（期望值：bbr）"

  if [[ " $available_congestion_control " != *" bbr "* ]]; then
    echo "当前运行内核未发现BBR支持。"
    echo "如果刚升级过内核，请重启进入新内核后重试；否则单纯重启通常无法解决，请确认内核支持tcp_bbr。"
  else
    echo "当前内核支持BBR，请检查上方sysctl输出中的错误后重试。一般不需要重启。"
  fi

  return 1
}

status_menu() {
  bash "$script_dir/serverstatus.sh"
}

download_and_run_script() (
  local script_name="$1"
  local remote_url="$2"
  local tmp_path

  if ! command -v wget >/dev/null 2>&1; then
    echo "缺少 wget，请先安装 wget 和 ca-certificates。"
    exit 1
  fi
  if ! tmp_path="$(mktemp "/tmp/${script_name}.XXXXXX")"; then
    echo "无法创建临时文件，已取消。"
    exit 1
  fi
  trap 'rm -f "$tmp_path"' EXIT

  echo "将从远程下载并执行: ${remote_url}"
  if wget -T 30 -t 2 -qO "$tmp_path" "$remote_url" && [[ -s "$tmp_path" ]] && bash -n "$tmp_path"; then
    bash "$tmp_path"
  else
    echo "下载失败或脚本无效，已取消；请检查网络及 ca-certificates。"
    exit 1
  fi
)

run_local_or_remote() {
  local script_name="$1"
  local local_path="$2"
  local remote_url="$3"

  local pull_remote
  read -r -p "是否从远程拉取最新脚本后执行？[y/N]: " pull_remote || return 0
  if [[ "$pull_remote" =~ ^[Yy]$ ]]; then
    download_and_run_script "$script_name" "$remote_url"
  else
    bash "$local_path"
  fi
}

run_use_sshkey() {
  run_local_or_remote "use-sshkey.sh" "$script_dir/use-sshkey.sh" "$repo_base_url/use-sshkey.sh"
}

run_swap() {
  run_local_or_remote "swap.sh" "$script_dir/swap.sh" "$repo_base_url/swap.sh"
}

main_menu() {
  if [[ -f /etc/alpine-release && $EUID -ne 0 ]]; then
    echo "Alpine 请使用 root 执行此脚本。"
    return 1
  fi
  local choice
  while true; do
    clear
    cat <<'EOF'
初始化脚本菜单
1) 开启 BBR+FQ
2) 探针相关
3) 运行 use-sshkey.sh
4) 运行 swap.sh
0) 退出
EOF
    read -r -p "请选择: " choice || return 0
    case "$choice" in
      1)
        bbrfq
        pause || return 0
        ;;
      2)
        status_menu
        if [[ -f /etc/alpine-release ]]; then
          pause || return 0
        fi
        ;;
      3)
        run_use_sshkey
        pause || return 0
        ;;
      4)
        run_swap
        pause || return 0
        ;;
      0)
        exit 0
        ;;
      *)
        echo "无效选择"
        pause || return 0
        ;;
    esac
  done
}

main_menu
