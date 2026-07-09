# Nexus Install Scripts

Nexus Panel 和 Agent 的一键安装脚本。

## 安装面板

```bash
# 默认端口 6100
bash <(curl -fsSL https://raw.githubusercontent.com/TIUCSIB/nexus-install/master/install-panel.sh)

# 自定义端口
bash <(curl -fsSL https://raw.githubusercontent.com/TIUCSIB/nexus-install/master/install-panel.sh) --port 8080
```

## 安装 Agent

安装前请先在面板中：
1. **系统设置** → 获取 `Server Token`
2. **节点管理** → 创建节点，记下 `节点 ID`

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/TIUCSIB/nexus-install/master/install-agent.sh) \
  --panel https://your-panel.com \
  --token YOUR_SERVER_TOKEN \
  --node-id 1
```

### 参数说明

| 参数 | 说明 |
|------|------|
| `--panel` | 面板地址 |
| `--token` | Server Token（面板系统设置中获取） |
| `--node-id` | 节点 ID（面板节点管理中创建后查看） |
| `--port` | Stats API 端口（默认 9090） |
| `--dir` | 安装目录（默认 /opt/nexus-agent） |

### 管理命令

安装后可使用 `ns` 命令管理：

```bash
ns list              # 列出所有节点
ns status            # 查看运行状态
ns service restart   # 重启服务
ns service stop      # 停止服务
```