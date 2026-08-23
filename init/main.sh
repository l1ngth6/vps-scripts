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

  remove_bbr_lotserver
  if ! grep -q "^net.core.default_qdisc=fq$" /etc/sysctl.d/99-sysctl.conf 2>/dev/null; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.d/99-sysctl.conf
  fi
  if ! grep -q "^net.ipv4.tcp_congestion_control=bbr$" /etc/sysctl.d/99-sysctl.conf 2>/dev/null; then
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/99-sysctl.conf
  fi
  sysctl --system

  current_qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
  current_congestion_control="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
  available_congestion_control="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"

  if [[ "$current_qdisc" == "fq" && "$current_congestion_control" == "bbr" ]]; then
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

  if ! tmp_path="$(mktemp "/tmp/${script_name}.XXXXXX")"; then
    echo "无法创建临时文件，已取消。"
    exit 1
  fi
  trap 'rm -f "$tmp_path"' EXIT

  echo "将从远程下载并执行: ${remote_url}"
  if wget --no-check-certificate -qO "$tmp_path" "$remote_url"; then
    bash "$tmp_path"
  else
    echo "下载失败，已取消。"
    exit 1
  fi
)

run_local_or_remote() {
  local script_name="$1"
  local local_path="$2"
  local remote_url="$3"

  read -r -p "是否从远程拉取最新脚本后执行？[y/N]: " pull_remote
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
    read -r -p "请选择: " choice
    case "$choice" in
      1)
        bbrfq
        pause
        ;;
      2)
        status_menu
        ;;
      3)
        run_use_sshkey
        pause
        ;;
      4)
        run_swap
        pause
        ;;
      0)
        exit 0
        ;;
      *)
        echo "无效选择"
        pause
        ;;
    esac
  done
}

main_menu
