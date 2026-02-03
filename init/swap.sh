#!/usr/bin/env bash
Green="\033[32m"
Font="\033[0m"
Red="\033[31m" 

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
echo -e "${Green}请输入需要添加的swap，建议为内存的2倍！${Font}"
read -p "请输入swap数值:" swapsize

#检查是否存在swapfile
grep -q "swapfile" /etc/fstab

#如果不存在将为其创建swap
if [ $? -ne 0 ]; then
	echo -e "${Green}swapfile未发现，正在为其创建swapfile${Font}"
	fallocate -l ${swapsize}M /swapfile
	chmod 600 /swapfile
	mkswap /swapfile
	swapon /swapfile
	echo '/swapfile none swap defaults 0 0' >> /etc/fstab
         echo -e "${Green}swap创建成功，并查看信息：${Font}"
         cat /proc/swaps
         cat /proc/meminfo | grep Swap
else
	echo -e "${Red}swapfile已存在，swap设置失败，请先运行脚本删除swap后重新设置！${Font}"
fi
}

del_swap(){
#检查是否存在swapfile
grep -q "swapfile" /etc/fstab

#如果存在就将其移除
if [ $? -eq 0 ]; then
	echo -e "${Green}swapfile已发现，正在将其移除...${Font}"
	sed -i '/swapfile/d' /etc/fstab
	echo "3" > /proc/sys/vm/drop_caches
	swapoff -a
	rm -f /swapfile
    echo -e "${Green}swap已删除！${Font}"
else
	echo -e "${Red}swapfile未发现，swap删除失败！${Font}"
fi
}

set_swappiness(){
    current_swappiness=$(cat /proc/sys/vm/swappiness)
    echo -e "${Green}当前vm.swappiness值为: ${current_swappiness}${Font}"
    read -p "请输入新的swappiness值(0-100): " swappiness_val

    if [[ ! "$swappiness_val" =~ ^[0-9]+$ ]] || [ "$swappiness_val" -lt 0 ] || [ "$swappiness_val" -gt 100 ]; then
        echo -e "${Red}输入无效，请输入0-100之间的数字！${Font}"
        return
    fi

    if grep -q "^vm.swappiness" /etc/sysctl.conf; then
        sed -i "s/^vm.swappiness.*/vm.swappiness = ${swappiness_val}/" /etc/sysctl.conf
    else
        echo "vm.swappiness = ${swappiness_val}" >> /etc/sysctl.conf
    fi

    echo -e "${Green}配置已写入 /etc/sysctl.conf${Font}"

    read -p "是否立即生效(执行 sysctl -p)? [y/n]: " apply_now
    if [[ "$apply_now" == "y" || "$apply_now" == "Y" ]]; then
        sysctl -p
        echo -e "${Green}已立即生效，当前值为: $(cat /proc/sys/vm/swappiness)${Font}"
    else
        echo -e "${Green}配置将在下次重启后生效。${Font}"
    fi
}

#开始菜单
main(){
root_need
ovz_no
clear
echo -e "———————————————————————————————————————"
echo -e "${Green}Linux VPS一键添加/删除swap脚本${Font}"
echo -e "${Green}1、添加swap${Font}"
echo -e "${Green}2、删除swap${Font}"
echo -e "${Green}3、修改swap优先级(vm.swappiness)${Font}"
echo -e "———————————————————————————————————————"
read -p "请输入数字 [1-3]:" num
case "$num" in
    1)
    add_swap
    ;;
    2)
    del_swap
    ;;
    3)
    set_swappiness
    ;;
    *)
    clear
    echo -e "${Green}请输入正确数字 [1-3]${Font}"
    main
    ;;
    esac
}
main