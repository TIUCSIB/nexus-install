#!/bin/bash
# Nexus Panel Installer
# Usage: bash install-panel.sh [--port 6100] [--token GITHUB_TOKEN]
set -e

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
plain='\033[0m'

cur_dir=$(pwd)
install_dir="/opt/nexus"
github_repo="TIUCSIB/nexus"
port=6100
github_token=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --port)  port="$2"; shift 2 ;;
        --dir)   install_dir="$2"; shift 2 ;;
        --token) github_token="$2"; shift 2 ;;
        *)       shift ;;
    esac
done

[[ $EUID -ne 0 ]] && echo -e "${red}Error: must run as root!${plain}" && exit 1

if [[ -f /etc/redhat-release ]]; then release="centos"
elif cat /etc/issue 2>/dev/null | grep -Eqi "alpine"; then release="alpine"
elif cat /etc/issue 2>/dev/null | grep -Eqi "debian"; then release="debian"
elif cat /etc/issue 2>/dev/null | grep -Eqi "ubuntu"; then release="ubuntu"
elif cat /proc/version 2>/dev/null | grep -Eqi "debian"; then release="debian"
elif cat /proc/version 2>/dev/null | grep -Eqi "ubuntu"; then release="ubuntu"
elif cat /proc/version 2>/dev/null | grep -Eqi "centos|red hat|redhat|rocky|alma"; then release="centos"
else release="centos"; fi

arch=$(uname -m)
if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then arch="arm64"
else echo -e "${red}Unsupported: ${arch}${plain}"; exit 1; fi

echo -e "${cyan}========================================${plain}"
echo -e "${cyan}       Nexus Panel Installer            ${plain}"
echo -e "${cyan}========================================${plain}"
echo -e "  OS:     ${green}${release}${plain}"
echo -e "  Arch:   ${green}${arch}${plain}"
echo -e "  Port:   ${green}${port}${plain}"
echo -e "  Dir:    ${green}${install_dir}${plain}"
echo ""

install_deps() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install -y wget curl ca-certificates unzip 2>&1 | tail -1
    elif [[ x"${release}" == x"alpine" ]]; then
        apk add --no-cache wget curl ca-certificates unzip 2>&1 | tail -1
    else
        apt-get update -y 2>&1 | tail -1
        apt-get install -y wget curl ca-certificates unzip 2>&1 | tail -1
    fi
}

# 获取认证头
get_auth_header() {
    if [[ -n "${github_token}" ]]; then
        echo "Authorization: Bearer ${github_token}"
    elif command -v gh &>/dev/null && gh auth status 2>/dev/null; then
        echo "Authorization: Bearer $(gh auth token 2>/dev/null)"
    else
        echo ""
    fi
}

# 下载文件（带认证）
download_file() {
    local name="$1"
    local output="$2"
    local auth_header
    auth_header=$(get_auth_header)

    echo -e "  Downloading ${name}..."

    # 获取版本信息
    local ver=""
    if command -v gh &>/dev/null; then
        ver=$(gh release list -R "${github_repo}" --json tagName -q '.[0].tagName' 2>/dev/null || true)
    fi
    if [[ -z "${ver}" ]]; then
        ver=$(curl -sL "https://api.github.com/repos/${github_repo}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/' 2>/dev/null || true)
    fi
    if [[ -n "${ver}" ]]; then
        echo -e "  Version: ${green}v${ver}${plain}"
    fi

    # 方法1: CDN 直链下载（公开仓库可用）
    echo -e "  Trying CDN..."
    local url
    if [[ -n "${ver}" ]]; then
        url="https://github.com/${github_repo}/releases/download/v${ver}/${name}"
    else
        url="https://github.com/${github_repo}/releases/latest/download/${name}"
    fi
    if command -v wget &>/dev/null; then
        wget --no-check-certificate -q --show-progress -O "${output}" "${url}" 2>/dev/null || true
    else
        curl -sL -o "${output}" "${url}" 2>/dev/null || true
    fi
    if [[ -s "${output}" ]]; then
        echo -e "  ${green}OK (CDN)${plain}"
        chmod +x "${output}" 2>/dev/null || true
        return 0
    fi

    # 方法2: gh CLI 下载
    if command -v gh &>/dev/null; then
        echo -e "  Trying gh CLI..."
        if [[ -n "${ver}" ]]; then
            gh release download "v${ver}" -R "${github_repo}" -p "${name}" -O "${output}" --clobber 2>/dev/null
        else
            gh release download -R "${github_repo}" -p "${name}" -O "${output}" --clobber 2>/dev/null
        fi
        if [[ $? -eq 0 && -s "${output}" ]]; then
            echo -e "  ${green}OK (gh)${plain}"
            chmod +x "${output}" 2>/dev/null || true
            return 0
        fi
    fi

    # 方法3: API 下载（带认证，私有仓库用）
    if [[ -n "${auth_header}" ]]; then
        echo -e "  Trying API..."
        local release_data=$(curl -sL -H "${auth_header}" -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/${github_repo}/releases/latest" 2>/dev/null)
        local asset_id=$(echo "${release_data}" | grep -A20 "\"name\": \"${name}\"" | grep '"id"' | head -1 | sed -E 's/.*"id": ([0-9]+).*/\1/')
        if [[ -n "${asset_id}" ]]; then
            curl -sL -H "${auth_header}" -H "Accept: application/octet-stream" \
                "https://api.github.com/repos/${github_repo}/releases/assets/${asset_id}" \
                -o "${output}" 2>/dev/null || true
            if [[ -s "${output}" ]]; then
                echo -e "  ${green}OK (API)${plain}"
                chmod +x "${output}" 2>/dev/null || true
                return 0
            fi
        fi
    fi

    # 全部失败
    rm -f "${output}" 2>/dev/null || true
    return 1
}

download_binary() {
    local name="nexus-linux-${arch}"
    if download_file "${name}" "${install_dir}/nexus"; then
        chmod +x "${install_dir}/nexus"
        echo -e "  Binary: ${green}OK${plain}"
    else
        echo -e "  Binary: ${red}FAILED${plain}"
        echo -e "  ${yellow}无法下载 ${name}${plain}"
        echo -e "  ${yellow}请检查网络连接后重试${plain}"
        exit 1
    fi
}

download_web() {
    local name="web-dist.zip"
    echo -e "  Downloading web assets..."
    if download_file "${name}" "${install_dir}/web-dist.zip"; then
        mkdir -p "${install_dir}/web/dist"
        unzip -o "${install_dir}/web-dist.zip" -d "${install_dir}/web/dist" >/dev/null 2>&1 || true
        rm -f "${install_dir}/web-dist.zip"
        echo -e "  Web: ${green}OK${plain}"
    else
        echo -e "  Web: ${yellow}skipped${plain}"
        mkdir -p "${install_dir}/web/dist"
    fi
}

gen_random() { cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w $1 | head -n 1; }

create_config() {
    if [[ ! -f "${install_dir}/config.yaml" ]]; then
        local sk=$(gen_random 32)
        local js=$(gen_random 32)
        cat > "${install_dir}/config.yaml" << EOF
app:
  name: "Nexus"
  debug: false
  secret_key: "${sk}"
server:
  host: "0.0.0.0"
  port: ${port}
database:
  driver: "sqlite"
  dsn: "data/nexus.db"
jwt:
  secret: "${js}"
  expire_hours: 72
node:
  heartbeat_interval: 30
  offline_timeout: 90
subscription:
  traffic_reset_days: 30
  plan_sort: 0
payment:
  enabled: false
  gateways: []
EOF
        echo -e "  Config: ${green}created (port ${port})${plain}"
    else
        echo -e "  Config: ${yellow}exists, updating port...${plain}"
        sed -i "s/^  port:.*/  port: ${port}/" "${install_dir}/config.yaml"
    fi
}

create_service() {
    if [[ x"${release}" == x"alpine" ]]; then
        cat << 'SVCEOF' > /etc/init.d/nexus
#!/sbin/openrc-run
name="nexus"
description="Nexus Panel"
command="/opt/nexus/nexus"
command_args="-config /opt/nexus/config.yaml"
command_background=true
pidfile="/var/run/${SVCNAME}.pid"
command_user="root"

depend() { need net; }

start_pre() {
    mkdir -p /var/run
}
SVCEOF
        chmod +x /etc/init.d/nexus
        rc-update add nexus default
    else
        cat << 'SVCEOF' > /etc/systemd/system/nexus.service
[Unit]
Description=Nexus Panel
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/nexus
ExecStart=/opt/nexus/nexus -config /opt/nexus/config.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF
        systemctl daemon-reload
        systemctl enable nexus >/dev/null 2>&1
    fi
    echo -e "  Service: ${green}created${plain}"
}

echo -e "${yellow}[1/6]${plain} Dependencies..."
install_deps

echo -e "${yellow}[2/6]${plain} Directories..."
mkdir -p "${install_dir}/data" "${install_dir}/web/dist"

echo -e "${yellow}[3/6]${plain} Binary..."
download_binary

echo -e "${yellow}[4/6]${plain} Web assets..."
download_web

echo -e "${yellow}[5/6]${plain} Config..."
create_config

echo -e "${yellow}[6/6]${plain} Service..."
create_service

if [[ x"${release}" == x"alpine" ]]; then rc-service nexus start 2>/dev/null
else systemctl start nexus 2>/dev/null; fi
sleep 2

server_ip=$(curl -s4 ifconfig.me 2>/dev/null || curl -s ip.sb 2>/dev/null || echo "YOUR_IP")

echo ""
echo -e "${green}========================================${plain}"
echo -e "${green}  Nexus Panel installed successfully!   ${plain}"
echo -e "${green}========================================${plain}"
echo ""
echo -e "  URL:     ${cyan}http://${server_ip}:${port}${plain}"
echo -e "  Login:   ${yellow}admin@nexus.com / 12345678${plain}"
echo ""
echo -e "  rc-service nexus start/stop/restart"
echo ""
cd "${cur_dir}"