#!/usr/bin/env bash
set -euo pipefail

# ===== Colors =====
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

die() { echo -e "${RED}错误: $*${NC}" >&2; exit 1; }

# ===== 0) Elevate to root if needed =====
if [ "${EUID}" -ne 0 ]; then
  if [[ -f /etc/alpine-release ]]; then
    die "Alpine 请使用 root 执行此脚本。"
  fi
  command -v sudo >/dev/null 2>&1 || die "请使用 root 执行，或先安装 sudo。"
  echo -e "${YELLOW}需要 Root 权限来修改 SSH 配置，正在尝试 sudo 提权...${NC}"
  exec sudo -E bash "$0" "$@"
fi

for cmd in sshd ssh-keygen; do
  command -v "$cmd" >/dev/null 2>&1 || die "缺少 $cmd，请先安装 OpenSSH（Alpine: apk add openssh openssh-keygen；Debian: apt install openssh-server）。"
done

# ===== 1) Determine target user/home =====
# Prefer original sudo user; otherwise root.
TARGET_USER="${SUDO_USER:-root}"
if command -v getent >/dev/null 2>&1; then
  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
else
  TARGET_HOME="$(awk -F: -v user="$TARGET_USER" '$1 == user { print $6; exit }' /etc/passwd)"
fi
[ -n "$TARGET_HOME" ] || die "无法获取用户 $TARGET_USER 的 home 目录"
TARGET_GROUP="$(id -gn "$TARGET_USER")"

echo -e "${GREEN}=== Debian / Alpine SSH Key 快速配置脚本 ===${NC}"
echo "目标用户: $TARGET_USER"
echo "目标HOME: $TARGET_HOME"
echo ""

# ===== 2) Read & validate public key =====
echo -e "${YELLOW}[步骤 1/2] 添加公钥${NC}"
echo "请粘贴你的公钥（通常以 ssh-ed25519 / ssh-rsa / ecdsa- / sk- 开头）。"
echo "粘贴完成后：按 Enter 换行，然后按 Ctrl-D 结束输入。"
echo "------------------------------------------------------"

INPUT_ALL="$(cat || true)"

# Extract first line that looks like a public key
USER_KEY="$(
  printf "%s\n" "$INPUT_ALL" | awk '
    {
      gsub(/\r/,"")
      line=$0
      sub(/^[ \t]+/, "", line)
      sub(/[ \t]+$/, "", line)
      if (line ~ /^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)[ \t]+/) {
        gsub(/[ \t]+/, " ", line)
        print line
        exit
      }
    }
  '
)"

[ -n "${USER_KEY:-}" ] || die "未识别到有效公钥。请确认粘贴的是一整行公钥。"

# Validate the key data and display its fingerprint before writing.
printf '%s\n' "$USER_KEY" | ssh-keygen -lf /dev/stdin || die "公钥数据无效。"

SSH_DIR="$TARGET_HOME/.ssh"
AUTH_FILE="$SSH_DIR/authorized_keys"

mkdir -p "$SSH_DIR"
touch "$AUTH_FILE"

# De-dup by exact whole line match
if grep -qxF "$USER_KEY" "$AUTH_FILE"; then
  echo -e "${YELLOW}提示: 该公钥已存在于 $AUTH_FILE，跳过写入。${NC}"
else
  printf '\n%s\n' "$USER_KEY" >> "$AUTH_FILE"
  echo -e "${GREEN}成功: 公钥已写入 $AUTH_FILE${NC}"
fi

# Permissions & ownership (important)
chmod 700 "$SSH_DIR"
chmod 600 "$AUTH_FILE"
chown "$TARGET_USER:$TARGET_GROUP" "$SSH_DIR" "$AUTH_FILE"

echo -e "${GREEN}权限已设置: ~/.ssh=700, authorized_keys=600，属主=$TARGET_USER${NC}"
echo "------------------------------------------------------"

# ===== 3) SSH hardening via sshd_config.d (recommended) =====
echo -e "${YELLOW}[步骤 2/2] 修改 SSH 登录方式${NC}"
read -r -p "是否禁用密码登录（仅允许密钥）？[y/N] " response || response=n

reload_ssh() {
  if [[ -f /etc/alpine-release ]]; then
    rc-service sshd reload
  else
    systemctl reload ssh || systemctl reload sshd
  fi
}

rollback_ssh() {
  local exit_status=$?
  trap - EXIT
  echo -e "${RED}SSH 配置未能应用，正在恢复备份...${NC}" >&2
  cp -p "$BACKUP_DIR/sshd_config" "$SSHD_CONFIG"
  if [[ -f "$BACKUP_DIR/key-only.conf" ]]; then
    cp -p "$BACKUP_DIR/key-only.conf" "$HARDEN_FILE"
  else
    rm -f "$HARDEN_FILE"
  fi
  if ! sshd -t || ! reload_ssh; then
    echo "配置恢复或服务重新加载失败，请保留当前会话并检查 SSH 服务。" >&2
  fi
  rm -f "$BACKUP_DIR/sshd_config" "$BACKUP_DIR/key-only.conf"
  rmdir "$BACKUP_DIR"
  exit "$exit_status"
}

if [[ "${response:-}" =~ ^([yY]([eE][sS])?)$ ]]; then
  if [[ -f /etc/alpine-release ]]; then
    command -v rc-service >/dev/null 2>&1 || die "缺少 rc-service，请先安装 openrc。"
  else
    command -v systemctl >/dev/null 2>&1 || die "缺少 systemctl，此脚本需要 systemd 或 Alpine OpenRC。"
  fi
  SSHD_CONFIG="/etc/ssh/sshd_config"
  SSHD_DIR="/etc/ssh/sshd_config.d"
  HARDEN_FILE="$SSHD_DIR/99-key-only.conf"

  mkdir -p "$SSHD_DIR"
  BACKUP_DIR="$(mktemp -d /tmp/ssh-key-helper.XXXXXX)"
  cp -p "$SSHD_CONFIG" "$BACKUP_DIR/sshd_config"
  if [ -f "$HARDEN_FILE" ]; then
    cp -p "$HARDEN_FILE" "$BACKUP_DIR/key-only.conf"
  fi
  trap rollback_ssh EXIT

  cat > "$HARDEN_FILE" <<'EOF'
# Managed by ssh-key-helper script
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
EOF
  chmod 644 "$HARDEN_FILE"

  # OpenSSH uses the first value it reads. Load our file before other settings.
  INCLUDE_LINE="Include $HARDEN_FILE"
  if [[ "$(head -n 1 "$SSHD_CONFIG")" != "$INCLUDE_LINE" ]]; then
    { printf '%s\n' "$INCLUDE_LINE"; cat "$BACKUP_DIR/sshd_config"; } > "$SSHD_CONFIG"
  fi

  echo "正在检查 SSH 配置及实际登录方式..."
  sshd -t || die "sshd -t 检查失败。"
  SSHD_TEST_CONTEXT="user=$TARGET_USER,addr=127.0.0.1"
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    read -r CLIENT_ADDR _ LOCAL_ADDR LOCAL_PORT <<< "$SSH_CONNECTION"
    SSHD_TEST_CONTEXT="user=$TARGET_USER,addr=$CLIENT_ADDR,laddr=$LOCAL_ADDR,lport=$LOCAL_PORT"
  fi
  EFFECTIVE_CONFIG="$(sshd -T -C "$SSHD_TEST_CONTEXT")" || die "无法读取 SSH 生效配置。"
  for setting in 'pubkeyauthentication yes' 'passwordauthentication no' 'kbdinteractiveauthentication no'; do
    grep -qxF "$setting" <<< "$EFFECTIVE_CONFIG" || die "SSH 配置未生效: $setting，请检查 Match 等自定义配置。"
  done
  reload_ssh || die "重新加载 SSH 服务失败。"
  trap - EXIT
  rm -f "$BACKUP_DIR/sshd_config" "$BACKUP_DIR/key-only.conf"
  rmdir "$BACKUP_DIR"
  echo -e "${GREEN}=== 全部完成！已禁用密码登录并重新加载 SSH ===${NC}"
  echo -e "${RED}重要提示：不要关闭当前会话！${NC}"
  echo "请新开一个终端窗口测试："
  echo "  ssh -i <你的私钥> $TARGET_USER@<服务器IP>"
  echo "确认可以用密钥登录后，再关闭当前窗口。"
else
  echo -e "${GREEN}已跳过修改密码登录设置，保留现有配置。${NC}"
  echo "建议你先测试密钥登录是否正常："
  echo "  ssh -i <你的私钥> $TARGET_USER@<服务器IP>"
fi
