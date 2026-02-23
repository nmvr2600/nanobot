# nanobot 部署脚本

## 使用方法

```bash
# 查看帮助
./scripts/deploy.sh help

# 完整部署（推荐）
./scripts/deploy.sh deploy

# 单独命令
./scripts/deploy.sh status    # 检查状态
./scripts/deploy.sh update    # 更新代码
./scripts/deploy.sh install   # 安装
./scripts/deploy.sh start     # 启动
./scripts/deploy.sh stop      # 停止
./scripts/deploy.sh restart   # 重启
./scripts/deploy.sh logs -f   # 查看日志
```

## 功能特性

- 支持 macOS launchd 和通用后台进程两种模式
- 自动检测 uv 或 pip 包管理器
- 完整的日志管理
- 优雅的进程停止（SIGTERM -> SIGKILL）
- 彩色输出，易于阅读
