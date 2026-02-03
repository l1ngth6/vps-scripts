#!/bin/bash
set -euo pipefail

# ===== Colors =====
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

die() { echo -e "${RED}错误: $*${NC}" >&2; exit 1; }

# ===== 0) Elevate to root if needed =====
if [ "${EUID}" -ne 0 ]; then
  echo -e "${YELLOW}需要 Root 权限来修改 SSH 配置，正在尝试 sudo 提权...${NC}"
  exec sudo -E bash "$0" "$@"
fi

# ===== 1) Determine target user/home =====
# Prefer original sudo user; otherwise root.
TARGET_USER="${SUDO_USER:-root}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
[ -n "$TARGET_HOME" ] || die "无法获取用户 $TARGET_USER 的 home 目录"

echo -e "${GREEN}=== Debian 12/13 SSH Key 快速配置脚本 ===${NC}"
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

# Lightweight validation: keytype + base64
if ! [[ "$USER_KEY" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)[[:space:]]+[A-Za-z0-9+/]+=*([[:space:]].*)?$ ]]; then
  die "公钥格式看起来不正确（需要: keytype + base64）。"
fi

SSH_DIR="$TARGET_HOME/.ssh"
AUTH_FILE="$SSH_DIR/authorized_keys"

mkdir -p "$SSH_DIR"
touch "$AUTH_FILE"

# De-dup by exact whole line match
if grep -qxF "$USER_KEY" "$AUTH_FILE"; then
  echo -e "${YELLOW}提示: 该公钥已存在于 $AUTH_FILE，跳过写入。${NC}"
else
  echo "$USER_KEY" >> "$AUTH_FILE"
  echo -e "${GREEN}成功: 公钥已写入 $AUTH_FILE${NC}"
fi

# Permissions & ownership (important)
chmod 700 "$SSH_DIR"
chmod 600 "$AUTH_FILE"
chown -R "$TARGET_USER:$TARGET_USER" "$SSH_DIR"

echo -e "${GREEN}权限已设置: ~/.ssh=700, authorized_keys=600，属主=$TARGET_USER${NC}"
echo "------------------------------------------------------"

# ===== 3) SSH hardening via sshd_config.d (recommended) =====
echo -e "${YELLOW}[步骤 2/2] 修改 SSH 登录方式${NC}"
read -r -p "是否禁用密码登录（仅允许密钥）？[y/N] " response

if [[ "${response:-}" =~ ^([yY]([eE][sS])?)$ ]]; then
  SSHD_DIR="/etc/ssh/sshd_config.d"
  HARDEN_FILE="$SSHD_DIR/99-key-only.conf"

  mkdir -p "$SSHD_DIR"

  # Backup if exists
  if [ -f "$HARDEN_FILE" ]; then
    BACKUP="$HARDEN_FILE.bak.$(date +%F_%H%M%S)"
    cp "$HARDEN_FILE" "$BACKUP"
    echo "已备份旧覆盖文件到: $BACKUP"
  fi

  cat > "$HARDEN_FILE" <<'EOF'
# Managed by ssh-key-helper script
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
EOF

  echo -e "${GREEN}已写入覆盖配置: $HARDEN_FILE${NC}"

  echo "正在检查 SSH 配置语法 (sshd -t)..."
  if sshd -t; then
    echo "语法检查通过，正在重启 SSH 服务..."
    systemctl restart ssh || systemctl restart sshd
    echo -e "${GREEN}=== 全部完成！已禁用密码登录并重启 SSH ===${NC}"
    echo -e "${RED}重要提示：不要关闭当前会话！${NC}"
    echo "请新开一个终端窗口测试："
    echo "  ssh -i <你的私钥> $TARGET_USER@<服务器IP>"
    echo "确认可以用密钥登录后，再关闭当前窗口。"
  else
    echo -e "${RED}错误: sshd -t 检查失败，正在回滚...${NC}"
    rm -f "$HARDEN_FILE"
    if [ -n "${BACKUP:-}" ] && [ -f "${BACKUP:-}" ]; then
      cp "$BACKUP" "$HARDEN_FILE"
      echo "已恢复备份覆盖文件。"
    fi
    die "已回滚。请检查 SSH 配置后重试。"
  fi
else
  echo -e "${GREEN}已跳过禁用密码登录。当前仍可使用密码登录。${NC}"
  echo "建议你先测试密钥登录是否正常："
  echo "  ssh -i <你的私钥> $TARGET_USER@<服务器IP>"
fi
