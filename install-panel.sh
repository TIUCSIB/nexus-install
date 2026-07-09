#!/bin/bash
# Nexus Panel Installer
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/TIUCSIB/nexus-install/master/install-panel.sh) [--port 6100]
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

while [[ $# -gt 0 ]]; do
    case $1 in
        --port)  port="$2"; shift 2 ;;
        --dir)   install_dir="$2"; shift 2 ;;
        *)       version="$1"; shift ;;
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

# 获取最新版本号
get_latest_version() {
    local ver=""
    # 方法1: gh CLI
    if command -v gh &>/dev/null; then
        ver=$(gh release list -R "${github_repo}" --json tagName -q '.[0].tagName' 2>/dev/null || true)
    fi
    # 方法2: API
    if [[ -z "${ver}" ]]; then
        ver=$(curl -sL "https://api.github.com/repos/${github_repo}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/' 2>/dev/null || true)
    fi
    echo "${ver}"
}

# 下载文件（多种方式，按优先级）
download_file() {
    local name="$1"      # 文件名，如 nexus-linux-amd64
    local output="$2"    # 输出路径
    local ver="${version:-$(get_latest_version)}"

    if [[ -n "${ver}" ]]; then
        echo -e "  Version: ${green}${ver}${plain}"
    else
        echo -e "  Version: ${yellow}latest${plain}"
    fi

    # 方法1: gh CLI 下载（最可靠，无需登录）
    if command -v gh &>/dev/null; then
        echo -e "  Downloading via gh CLI..."
        if [[ -n "${ver}" ]]; then
            gh release download "${ver}" -R "${github_repo}" -p "${name}" -O "${output}" --clobber 2>/dev/null
        else
            gh release download -R "${github_repo}" -p "${name}" -O "${output}" --clobber 2>/dev/null
        fi
        if [[ $? -eq 0 && -s "${output}" ]]; then
            echo -e "  ${green}OK${plain}"
            chmod +x "${output}" 2>/dev/null || true
            return 0
        fi
    fi

    # 方法2: API 下载
    echo -e "  Downloading via API..."
    local api_url asset_id
    if [[ -n "${ver}" ]]; then
        api_url="https://api.github.com/repos/${github_repo}/releases/tags/v${ver}"
        asset_id=$(curl -sL "${api_url}" 2>/dev/null | grep -A20 "\"name\": \"${name}\"" | grep '"id"' | head -1 | sed -E 's/.*"id": ([0-9]+).*/\1/')
    fi
    if [[ -z "${asset_id}" ]]; then
        api_url="https://api.github.com/repos/${github_repo}/releases/latest"
        asset_id=$(curl -sL "${api_url}" 2>/dev/null | grep -A20 "\"name\": \"${name}\"" | grep '"id"' | head -1 | sed -E 's/.*"id": ([0-9]+).*/\1/')
    fi
    if [[ -n "${asset_id}" ]]; then
        curl -sL -H "Accept: application/octet-stream" \
            "https://api.github.com/repos/${github_repo}/releases/assets/${asset_id}" \
            -o "${output}" 2>/dev/null || true
        if [[ -s "${output}" ]]; then
            echo -e "  ${green}OK${plain}"
            chmod +x "${output}" 2>/dev/null || true
            return 0
        fi
    fi

    # 方法3: 直接 CDN URL 下载（最不稳定）
    echo -e "  Downloading via CDN..."
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
        echo -e "  ${green}OK${plain}"
        chmod +x "${output}" 2>/dev/null || true
        return 0
    fi

    # 全部失败
    rm -f "${output}" 2>/dev/null || true
    return 1
}

install_deps() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install -y wget curl ca-certificates >/dev/null 2>&1
    elif [[ x"${release}" == x"alpine" ]]; then
        apk add --no-cache wget curl ca-certificates unzip github-cli >/dev/null 2>&1
    else
        apt-get update -y >/dev/null 2>&1
        apt-get install -y wget curl ca-certificates unzip >/dev/null 2>&1
    fi
}

download_binary() {
    local name="nexus-linux-${arch}"
    echo -e "  Downloading ${name}..."
    if download_file "${name}" "${install_dir}/nexus"; then
        chmod +x "${install_dir}/nexus"
        echo -e "  Binary: ${green}OK${plain}"
    else
        echo -e "  Binary: ${red}FAILED${plain}"
        echo -e "  ${yellow}Tip: 请手动安装 github-cli 后重试${plain}"
        echo -e "  ${yellow}Alpine: apk add github-cli${plain}"
        echo -e "  ${yellow}Debian: apt install gh${plain}"
        echo -e "  ${yellow}CentOS: yum install gh${plain}"
        exit 1
    fi
}

download_web() {
    local name="web-dist.zip"
    echo -e "  Downloading web assets..."
    if download_file "${name}" "${install_dir}/web-dist.zip"; then
        mkdir -p "${install_dir}/web/dist"
        unzip -o "${install_dir}/web-dist.zip" -d "${install_dir}/web/dist" >/dev/null 2>&1
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
command="/opt/nexus/nexus"
command_args="-config /opt/nexus/config.yaml"
command_background="yes"
depend() { need net; }
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

if [[ -n "$2" && -n "$3" ]]; then
    echo -e "  Admin: $2"
    "${install_dir}/nexus" -config "${install_dir}/config.yaml" -admin-email "$2" -admin-pass "$3"
fi

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