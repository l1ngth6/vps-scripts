#!/usr/bin/env bash
Green="\033[32m"
Font="\033[0m"
Red="\033[31m" 

pause(){
    read -r -p "按回车继续..." _
}

#root权限
root_need(){
    if [[ $EUID -ne 0 ]]; then
        echo -e "${Red}Error:This script must be run as root!${Font}"
        exit 1
    fi
}

#检测ovz
ovz_no(){
    if [[ -d "/proc/vz" ]]; then
        echo -e "${Red}Your VPS is based on OpenVZ，not supported!${Font}"
        exit 1
    fi
}

add_swap(){
    local swapsize
    echo -e "${Green}请输入需要添加的 swap 大小，单位 MiB。${Font}"
    read -r -p "请输入swap数值:" swapsize || return 0
    if [[ ! "$swapsize" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${Red}请输入大于 0 的整数！${Font}"
        return 1
    fi

    if [[ -e /swapfile || -L /swapfile ]] || swap_is_active \
        || grep -Eq '^[[:space:]]*/swapfile[[:space:]]' /etc/fstab 2>/dev/null; then
        echo -e "${Red}/swapfile 或其配置已存在，请先检查或删除后再创建。${Font}"
        return 1
    fi

    echo -e "${Green}正在创建 /swapfile...${Font}"
    if ! (
        umask 077
        if command -v fallocate >/dev/null 2>&1; then
            fallocate -l "${swapsize}M" /swapfile
        else
            dd if=/dev/zero of=/swapfile bs=1048576 count="$swapsize"
        fi
    ); then
        rm -f /swapfile
        echo -e "${Red}创建失败，请检查磁盘空间和文件系统。${Font}"
        return 1
    fi

    if ! chmod 600 /swapfile || ! mkswap /swapfile || ! swapon /swapfile; then
        rm -f /swapfile
        echo -e "${Red}swap 初始化或启用失败，已清理本次创建的文件。${Font}"
        return 1
    fi

    if ! echo '/swapfile none swap defaults 0 0' >> /etc/fstab; then
        echo -e "${Red}写入 fstab 失败，正在撤销本次创建的 swap。${Font}"
        swapoff /swapfile && rm -f /swapfile
        return 1
    fi
    if [[ -f /etc/alpine-release ]] && ! rc-update add swap boot; then
        echo -e "${Red}swap 已启用并写入 fstab，但设置开机启用失败，请执行 rc-update add swap boot。${Font}"
        return 1
    fi

    echo -e "${Green}swap创建成功，并查看信息：${Font}"
    cat /proc/swaps
    grep Swap /proc/meminfo
}

swap_is_active(){
    awk '$1 == "/swapfile" { found = 1 } END { exit !found }' /proc/swaps
}

del_swap(){
    if [[ ! -e /swapfile && ! -L /swapfile ]] && ! swap_is_active \
        && ! grep -Eq '^[[:space:]]*/swapfile[[:space:]]' /etc/fstab 2>/dev/null; then
        echo -e "${Red}未发现 /swapfile 或其配置。${Font}"
        return 1
    fi

    if swap_is_active && ! swapoff /swapfile; then
        echo -e "${Red}关闭 /swapfile 失败，已保留文件和 fstab 配置。${Font}"
        return 1
    fi
    if [[ -f /etc/fstab ]]; then
        sed -i '/^[[:space:]]*\/swapfile[[:space:]]/d' /etc/fstab || return 1
    fi
    rm -f /swapfile || return 1
    echo -e "${Green}/swapfile 已删除。${Font}"
}

set_swappiness(){
    local current_swappiness swappiness_val apply_now
    current_swappiness=$(cat /proc/sys/vm/swappiness)
    echo -e "${Green}当前vm.swappiness值为: ${current_swappiness}${Font}"
    read -r -p "请输入新的swappiness值(0-100): " swappiness_val || return 0

    if [[ ! "$swappiness_val" =~ ^[0-9]+$ ]] || [ "$swappiness_val" -lt 0 ] || [ "$swappiness_val" -gt 100 ]; then
        echo -e "${Red}输入无效，请输入0-100之间的数字！${Font}"
        return 1
    fi

    # 确保配置文件存在
    if [ ! -f "/etc/sysctl.conf" ]; then
        touch "/etc/sysctl.conf" || return 1
    fi

    if grep -q '^[[:space:]]*vm\.swappiness[[:space:]]*=' /etc/sysctl.conf; then
        sed -i "s/^[[:space:]]*vm\.swappiness[[:space:]]*=.*/vm.swappiness = ${swappiness_val}/" /etc/sysctl.conf || return 1
    else
        echo "vm.swappiness = ${swappiness_val}" >> /etc/sysctl.conf || return 1
    fi

    echo -e "${Green}配置已写入 /etc/sysctl.conf${Font}"

    read -r -p "是否立即生效(执行 sysctl -p)? [y/n]: " apply_now || return 0
    if [[ "$apply_now" == "y" || "$apply_now" == "Y" ]]; then
        sysctl -p /etc/sysctl.conf || return 1
        echo -e "${Green}已立即生效，当前值为: $(cat /proc/sys/vm/swappiness)${Font}"
    else
        echo -e "${Green}配置将在下次重启后生效。${Font}"
    fi
}

#开始菜单
main(){
    root_need
    ovz_no
    local cmd num
    for cmd in mkswap swapon swapoff sysctl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "缺少 $cmd，请先安装 util-linux、procps（Debian）或检查 BusyBox（Alpine）。"
            return 1
        fi
    done
    if [[ -f /etc/alpine-release ]] && ! command -v rc-update >/dev/null 2>&1; then
        echo "缺少 rc-update，请先安装 openrc。"
        return 1
    fi

    while true; do
        clear
        echo -e "———————————————————————————————————————"
        echo -e "${Green}Linux VPS一键添加/删除swap脚本${Font}"
        echo -e "${Green}1、添加swap${Font}"
        echo -e "${Green}2、删除swap${Font}"
        echo -e "${Green}3、修改换页倾向(vm.swappiness)${Font}"
        echo -e "${Green}0、完成并返回初始化菜单${Font}"
        echo -e "———————————————————————————————————————"
        if ! read -r -p "请输入数字 [0-3]:" num; then
            return 0
        fi

        case "$num" in
        1)
            add_swap
            pause || return 0
            ;;
        2)
            del_swap
            pause || return 0
            ;;
        3)
            set_swappiness
            pause || return 0
            ;;
        0)
            return
            ;;
        *)
            echo -e "${Green}请输入正确数字 [0-3]${Font}"
            pause || return 0
            ;;
        esac
    done
}
main
