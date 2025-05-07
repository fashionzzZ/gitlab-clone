# GitLab批量克隆工具

一个功能强大的Bash脚本，用于批量克隆GitLab上的项目，保持原始目录结构，支持并行克隆以提高效率。

## 功能特点

- 批量克隆GitLab上某个组及其子组下的所有项目
- 保持原始目录结构，完整还原GitLab上的组织架构
- 支持并行克隆，显著提高克隆效率
- 支持断点续传（自动跳过已存在的目录）
- 支持日期过滤，只克隆特定日期后更新的项目
- 支持多种克隆选项（深度、分支、协议等）
- 支持跳过已归档的项目
- 详细的日志记录和进度显示
- 支持SSH和HTTPS两种克隆协议

## 依赖项

- Bash (4.0+)
- Git
- jq (用于JSON解析)
- curl

## 安装方法

1. 下载脚本

```bash
curl -O https://raw.githubusercontent.com/fashionzzZ/gitlab-clone/main/gitlab-clone.sh
```

2. 添加执行权限

```bash
chmod +x gitlab-clone.sh
```

3. 安装依赖项

对于macOS:
```bash
brew install jq
```

对于Ubuntu/Debian:
```bash
apt-get install jq
```

对于CentOS/RHEL:
```bash
yum install jq
```

## 使用方法

```bash
./gitlab-clone.sh [选项]
```

### 参数说明

| 选项 | 长选项 | 描述 |
|------|--------|------|
| `-g` | `--gitlab-url` | GitLab服务器URL (例如: https://gitlab.example.com) |
| `-t` | `--token` | GitLab私人访问令牌 |
| `-n` | `--group-name` | 要克隆的组名称 |
| `-i` | `--group-id` | 要克隆的组ID (与组名称二选一) |
| `-o` | `--output-dir` | 输出目录 (默认: 当前目录) |
| `-d` | `--depth` | Git克隆深度 (可选，默认完整克隆) |
| `-b` | `--branch` | 要克隆的特定分支 (可选) |
| `-p` | `--protocol` | 克隆协议 (ssh或https, 默认: https) |
| `-s` | `--skip-archived` | 跳过已归档的项目 (可选) |
| `-j` | `--jobs` | 并行克隆的最大数量 (默认: 5) |
| `-a` | `--after-date` | 只克隆在指定日期之后更新的项目 (格式: YYYY-MM-DD) |
| `-l` | `--log-file` | 指定日志文件路径 (不指定则不生成日志文件) |
| `-h` | `--help` | 显示帮助信息 |

## 使用示例

### 基本用法

通过组名称克隆：
```bash
./gitlab-clone.sh -g https://gitlab.example.com -t your_token -n your_group -o /path/to/output
```

通过组ID克隆：
```bash
./gitlab-clone.sh -g https://gitlab.example.com -t your_token -i 123 -o /path/to/output
```

### 高级用法

使用SSH协议并设置克隆深度：
```bash
./gitlab-clone.sh -g https://gitlab.example.com -t your_token -n your_group -p ssh -d 1 -o /path/to/output
```

增加并行任务数量：
```bash
./gitlab-clone.sh -g https://gitlab.example.com -t your_token -n your_group -j 10 -o /path/to/output
```

只克隆特定日期后更新的项目：
```bash
./gitlab-clone.sh -g https://gitlab.example.com -t your_token -n your_group -a 2023-01-01 -o /path/to/output
```

克隆特定分支并跳过已归档项目：
```bash
./gitlab-clone.sh -g https://gitlab.example.com -t your_token -n your_group -b main -s -o /path/to/output
```

生成详细日志：
```bash
./gitlab-clone.sh -g https://gitlab.example.com -t your_token -n your_group -l clone_log.txt -o /path/to/output
```

## 获取GitLab访问令牌

1. 登录到您的GitLab账户
2. 点击右上角的用户头像，选择"Preferences"（偏好设置）
3. 在左侧菜单中选择"Access Tokens"（访问令牌）
4. 创建一个新的个人访问令牌，确保勾选`read_api`权限
5. 点击"Create personal access token"（创建个人访问令牌）
6. 复制生成的令牌（注意：令牌只会显示一次）

## 注意事项

- 对于大型组织，建议增加并行任务数量(`-j`选项)以提高效率
- 如果只需要最新代码，可以使用深度克隆(`-d 1`)减少下载量
- 使用日期过滤(`-a`选项)可以只克隆最近更新的项目，适合增量备份
- 脚本会自动跳过已存在的目录，支持断点续传
- 使用HTTPS协议时，令牌会自动添加到URL中，无需额外配置

## 贡献

欢迎提交问题和拉取请求！如果您有任何改进建议或功能需求，请创建一个issue。

## 许可证

[MIT](LICENSE)