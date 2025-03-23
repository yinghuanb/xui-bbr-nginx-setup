#!/bin/bash

# 脚本: x-ui-bbr-nginx-setup.sh
# 描述: 自动安装X-UI面板,配置BBR算法,安装Nginx并配置SSL证书
# 开发者: 樱花
# 版本: 1.1
# 支持: Ubuntu/Debian 和 CentOS/RHEL

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 确保脚本以root权限运行
if [ "$(id -u)" != "0" ]; then
   echo -e "${RED}错误: 此脚本必须以root权限运行${NC}" 1>&2
   exit 1
fi

# 检测系统类型
if [ -f /etc/debian_version ]; then
    OSTYPE="debian"
    echo -e "${GREEN}检测到 Debian/Ubuntu 系统${NC}"
elif [ -f /etc/redhat-release ]; then
    OSTYPE="centos"
    echo -e "${GREEN}检测到 CentOS/RHEL 系统${NC}"
else
    echo -e "${RED}不支持的操作系统类型${NC}"
    exit 1
fi

# 显示欢迎信息
echo -e "${GREEN}=================================================${NC}"
echo -e "${GREEN}      X-UI 面板、BBR和Nginx自动安装脚本         ${NC}"
echo -e "${GREEN}            开发者: 樱花                       ${NC}"
echo -e "${GREEN}=================================================${NC}"
echo ""

# 询问域名
read -p "请输入您的域名: " domain_name
if [ -z "$domain_name" ]; then
    echo -e "${RED}错误: 域名不能为空${NC}"
    exit 1
fi

echo -e "\n${YELLOW}开始安装...${NC}\n"

# 步骤1: 检查并启用BBR TCP拥塞控制算法
echo -e "${GREEN}[1/4] 检查并配置BBR拥塞控制算法...${NC}"

# 检查BBR是否已启用
if lsmod | grep -q bbr && sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
    echo -e "${YELLOW}BBR已经启用，跳过配置步骤${NC}"
else
    # 检查配置文件中是否已有BBR设置
    if grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf && grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${YELLOW}BBR已在配置文件中设置，正在应用...${NC}"
        sysctl -p
    else
        echo -e "${YELLOW}正在配置BBR...${NC}"
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
    fi
    
    # 验证BBR是否成功启用
    if lsmod | grep -q bbr && sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
        echo -e "${GREEN}BBR配置并启用成功${NC}"
    else
        echo -e "${YELLOW}BBR配置已完成，但可能需要重启系统才能生效${NC}"
    fi
fi

# 步骤2: 安装X-UI面板
echo -e "\n${GREEN}[2/4] 安装X-UI面板...${NC}"
bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)

# 步骤3: 安装Nginx
echo -e "\n${GREEN}[3/4] 安装Nginx...${NC}"

if [ "$OSTYPE" == "debian" ]; then
    # Debian/Ubuntu
    apt update
    apt install -y nginx
elif [ "$OSTYPE" == "centos" ]; then
    # CentOS/RHEL
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        if [ "$VERSION_ID" == "7" ]; then
            # CentOS 7
            yum install -y epel-release
            yum install -y nginx
        else
            # CentOS 8+
            dnf install -y epel-release
            dnf install -y nginx
        fi
    else
        # 老版本的CentOS
        yum install -y epel-release
        yum install -y nginx
    fi
fi

# 启动Nginx
systemctl enable nginx
systemctl start nginx
echo -e "${GREEN}Nginx已安装并启动，保留默认配置${NC}"

# 步骤4: 安装acme.sh并申请SSL证书
echo -e "\n${GREEN}[4/4] 安装acme.sh并申请SSL证书...${NC}"

# 安装依赖
if [ "$OSTYPE" == "debian" ]; then
    apt install -y socat curl
elif [ "$OSTYPE" == "centos" ]; then
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        if [ "$VERSION_ID" == "7" ]; then
            yum install -y socat curl
        else
            dnf install -y socat curl
        fi
    else
        yum install -y socat curl
    fi
fi

# 检查acme.sh是否已安装
if [ ! -f "/root/.acme.sh/acme.sh" ]; then
    curl https://get.acme.sh | sh
fi

# 添加软链接
if [ ! -f "/usr/local/bin/acme.sh" ]; then
    ln -s /root/.acme.sh/acme.sh /usr/local/bin/acme.sh
fi

# 切换CA机构
acme.sh --set-default-ca --server letsencrypt

# 申请证书
mkdir -p /var/www/html/.well-known/acme-challenge
chmod -R 755 /var/www/html
acme.sh --issue -d $domain_name -k ec-256 --webroot /var/www/html

# 安装证书
acme.sh --install-cert -d $domain_name --ecc --key-file /etc/x-ui/server.key --fullchain-file /etc/x-ui/server.crt --reloadcmd "systemctl force-reload nginx"

# 提示安装完成
echo -e "\n${GREEN}=================================================${NC}"
echo -e "${GREEN}            安装已完成!                          ${NC}"
echo -e "${GREEN}            开发者: 樱花                        ${NC}"
echo -e "${GREEN}=================================================${NC}"
echo -e "${YELLOW}X-UI面板已安装${NC}"
echo -e "${YELLOW}BBR拥塞控制算法已启用${NC}"
echo -e "${YELLOW}Nginx已安装并使用默认配置${NC}"
echo -e "${YELLOW}SSL证书已申请并安装到/etc/x-ui/目录${NC}"
echo -e "\n${YELLOW}证书位置: ${NC}"
echo -e "${YELLOW}  - 证书文件: /etc/x-ui/server.crt${NC}"
echo -e "${YELLOW}  - 密钥文件: /etc/x-ui/server.key${NC}"
echo -e "\n${GREEN}感谢使用此脚本! 开发者：樱花${NC}"
