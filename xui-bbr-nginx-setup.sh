#!/bin/bash

# 脚本: x-ui-bbr-nginx-setup.sh
# 描述: 自动安装X-UI面板,配置BBR算法,安装Nginx并配置SSL证书
# 开发者: 樱花
# 版本: 1.2
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
echo -e "${GREEN}[1/5] 检查并配置BBR拥塞控制算法...${NC}"

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
echo -e "\n${GREEN}[2/5] 安装X-UI面板...${NC}"
bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)

# 步骤3: 安装Nginx
echo -e "\n${GREEN}[3/5] 安装Nginx...${NC}"

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
echo -e "${GREEN}Nginx已安装并启动${NC}"

# 步骤4: 安装acme.sh并申请SSL证书
echo -e "\n${GREEN}[4/5] 安装acme.sh并申请SSL证书...${NC}"

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

echo -e "${GREEN}=================================================${NC}"
echo -e "${GREEN}      请配置以下参数                         ${NC}"
echo -e "${GREEN}=================================================${NC}"

# 询问伪装网址
read -p "请输入伪装网址(例如 https://pan.qiangsungroup.cn): " fake_site
if [ -z "$fake_site" ]; then
    echo -e "${RED}错误: 伪装网址不能为空${NC}"
    exit 1
fi

# 提取伪装网址的域名部分
fake_domain=$(echo "$fake_site" | sed -E 's|^https?://([^/]+).*|\1|')
echo -e "${GREEN}伪装域名: $fake_domain${NC}"

# 询问分流路径
read -p "请输入分流路径(例如 ray): " ray_path
if [ -z "$ray_path" ]; then
    ray_path="ray"
    echo -e "${YELLOW}使用默认分流路径: $ray_path${NC}"
fi

# 询问Xray端口
read -p "请输入Xray端口(默认 10000): " xray_port
if [ -z "$xray_port" ]; then
    xray_port="10000"
    echo -e "${YELLOW}使用默认Xray端口: $xray_port${NC}"
fi

# 询问X-UI路径
read -p "请输入X-UI路径(例如 xui): " xui_path
if [ -z "$xui_path" ]; then
    xui_path="xui"
    echo -e "${YELLOW}使用默认X-UI路径: $xui_path${NC}"
fi

# 询问X-UI端口
read -p "请输入X-UI端口(默认 9999): " xui_port
if [ -z "$xui_port" ]; then
    xui_port="9999"
    echo -e "${YELLOW}使用默认X-UI端口: $xui_port${NC}"
fi

# 步骤5: 配置Nginx
echo -e "\n${GREEN}[5/5] 配置Nginx...${NC}"

# 检测用于www-data的用户名
NGINX_USER="www-data"
if [ "$OSTYPE" == "centos" ]; then
    NGINX_USER="nginx"
fi

# 创建Nginx配置文件
cat > /etc/nginx/nginx.conf << EOF
user $NGINX_USER;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    gzip on;

    server {
        listen 443 ssl;
        
        server_name $domain_name;  #你的域名
        ssl_certificate       /etc/x-ui/server.crt;  #证书位置
        ssl_certificate_key   /etc/x-ui/server.key; #私钥位置
        
        ssl_session_timeout 1d;
        ssl_session_cache shared:MozSSL:10m;
        ssl_session_tickets off;
        ssl_protocols    TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers off;

        location / {
            proxy_pass $fake_site; #伪装网址
            proxy_redirect off;
            proxy_ssl_server_name on;
            sub_filter_once off;
            sub_filter "$fake_domain" \$server_name;
            proxy_set_header Host "$fake_domain";
            proxy_set_header Referer \$http_referer;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header User-Agent \$http_user_agent;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header Accept-Encoding "";
            proxy_set_header Accept-Language "zh-CN";
        }


        location /$ray_path {   #分流路径
            proxy_redirect off;
            proxy_pass http://127.0.0.1:$xray_port; #Xray端口
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }
        
        location /$xui_path {   #xui路径
            proxy_redirect off;
            proxy_pass http://127.0.0.1:$xui_port;  #xui监听端口
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
        }
    }

    server {
        listen 80;
        location /.well-known/ {
               root /var/www/html;
            }
        location / {
                rewrite ^(.*)$ https://\$host\$1 permanent;
            }
    }
}
EOF

# 如果是CentOS系统，需要处理CentOS特有的配置情况
if [ "$OSTYPE" == "centos" ]; then
    # 在CentOS中，modules-enabled文件夹可能不存在
    sed -i 's|include /etc/nginx/modules-enabled/\*.conf;|# include /etc/nginx/modules-enabled/\*.conf;|g' /etc/nginx/nginx.conf
    
    # 确保/etc/nginx/conf.d/目录存在
    mkdir -p /etc/nginx/conf.d
    
    # 备份并删除default.conf
    if [ -f /etc/nginx/conf.d/default.conf ]; then
        mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak
    fi
fi

# 重启Nginx以应用配置
echo -e "${GREEN}重启Nginx以应用配置...${NC}"
systemctl restart nginx

# 检查Nginx是否成功重启
if systemctl is-active --quiet nginx; then
    echo -e "${GREEN}Nginx重启成功${NC}"
else
    echo -e "${RED}Nginx重启失败，请检查配置错误${NC}"
    systemctl status nginx
fi

# 提示安装完成
echo -e "\n${GREEN}=================================================${NC}"
echo -e "${GREEN}            安装已完成!                          ${NC}"
echo -e "${GREEN}            开发者: 樱花                        ${NC}"
echo -e "${GREEN}=================================================${NC}"
echo -e "${YELLOW}X-UI面板已安装${NC}"
echo -e "${YELLOW}BBR拥塞控制算法已启用${NC}"
echo -e "${YELLOW}Nginx已安装并配置${NC}"
echo -e "${YELLOW}SSL证书已申请并安装${NC}"
echo -e "\n${YELLOW}您的配置信息:${NC}"
echo -e "${YELLOW}  - 域名: $domain_name${NC}"
echo -e "${YELLOW}  - 伪装网址: $fake_site${NC}"
echo -e "${YELLOW}  - 分流路径: /$ray_path${NC}"
echo -e "${YELLOW}  - Xray端口: $xray_port${NC}"
echo -e "${YELLOW}  - X-UI路径: /$xui_path${NC}"
echo -e "${YELLOW}  - X-UI端口: $xui_port${NC}"
echo -e "\n${YELLOW}访问方式:${NC}"
echo -e "${YELLOW}  - X-UI面板: https://$domain_name/$xui_path${NC}"
echo -e "\n${GREEN}感谢使用此脚本! 开发者：樱花 QQ：70026742${NC}"
