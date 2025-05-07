#!/bin/bash

# GitLab批量克隆脚本
# 功能：
# 1. 批量克隆GitLab上某个组及其子组下的所有项目，并保持原始目录结构
# 2. 支持并行克隆，提高效率
# 3. 支持断点续传（自动跳过已存在的目录）
# 4. 支持日期过滤，只克隆特定日期后更新的项目

# 检查jq是否安装
if ! command -v jq &> /dev/null; then
    echo "错误: 此脚本需要jq工具来解析JSON。请安装jq后再运行。"
    echo "安装方法："
    echo "  - macOS: brew install jq"
    echo "  - Ubuntu/Debian: apt-get install jq"
    echo "  - CentOS/RHEL: yum install jq"
    exit 1
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 使用说明
function show_usage {
    echo -e "${BLUE}GitLab批量克隆脚本${NC}"
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -g, --gitlab-url     GitLab服务器URL (例如: https://gitlab.example.com)"
    echo "  -t, --token          GitLab私人访问令牌"
    echo "  -n, --group-name     要克隆的组名称"
    echo "  -i, --group-id       要克隆的组ID (与组名称二选一)"
    echo "  -o, --output-dir     输出目录 (默认: 当前目录)"
    echo "  -d, --depth          Git克隆深度 (可选，默认完整克隆)"
    echo "  -b, --branch         要克隆的特定分支 (可选)"
    echo "  -p, --protocol       克隆协议 (ssh或https, 默认: https)"
    echo "  -s, --skip-archived  跳过已归档的项目 (可选)"
    echo "  -j, --jobs           并行克隆的最大数量 (默认: 5)"
    echo "  -a, --after-date     只克隆在指定日期之后更新的项目 (格式: YYYY-MM-DD)"
    echo "  -l, --log-file       指定日志文件路径 (不指定则不生成日志文件)"
    echo "  -h, --help           显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -g https://gitlab.example.com -t your_token -n your_group -o /path/to/output"
    echo "  $0 -g https://gitlab.example.com -t your_token -i 123 -o /path/to/output -p ssh -d 1"
    echo "  $0 -g https://gitlab.example.com -t your_token -n your_group -j 10 -o /path/to/output"
    echo "  $0 -g https://gitlab.example.com -t your_token -n your_group -a 2023-01-01"
    exit 1
}

# 参数解析
GITLAB_URL=""
TOKEN=""
GROUP_NAME=""
GROUP_ID=""
OUTPUT_DIR="$(pwd)"
CLONE_DEPTH=""
BRANCH=""
PROTOCOL="https"
SKIP_ARCHIVED=false
MAX_JOBS=5  # 默认并行任务数
AFTER_DATE=""
LOG_FILE=""  # 默认不生成日志文件

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -g|--gitlab-url)
            GITLAB_URL="$2"
            shift 2
            ;;
        -t|--token)
            TOKEN="$2"
            shift 2
            ;;
        -n|--group-name)
            GROUP_NAME="$2"
            shift 2
            ;;
        -i|--group-id)
            GROUP_ID="$2"
            shift 2
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -d|--depth)
            CLONE_DEPTH="$2"
            shift 2
            ;;
        -b|--branch)
            BRANCH="$2"
            shift 2
            ;;
        -p|--protocol)
            PROTOCOL="$2"
            shift 2
            ;;
        -s|--skip-archived)
            SKIP_ARCHIVED=true
            shift
            ;;
        -j|--jobs)
            MAX_JOBS="$2"
            shift 2
            ;;
        -a|--after-date)
            AFTER_DATE="$2"
            shift 2
            ;;
        -l|--log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            echo -e "${RED}错误: 未知选项 $1${NC}"
            show_usage
            ;;
    esac
done

# 验证必要参数
if [[ -z "$GITLAB_URL" ]]; then
    echo -e "${RED}错误: 必须提供GitLab URL${NC}"
    show_usage
fi

if [[ -z "$TOKEN" ]]; then
    echo -e "${RED}错误: 必须提供访问令牌${NC}"
    show_usage
fi

if [[ -z "$GROUP_NAME" && -z "$GROUP_ID" ]]; then
    echo -e "${RED}错误: 必须提供组名称或组ID${NC}"
    show_usage
fi

if [[ "$PROTOCOL" != "https" && "$PROTOCOL" != "ssh" ]]; then
    echo -e "${RED}错误: 协议必须是 'https' 或 'ssh'${NC}"
    show_usage
fi

# 验证并行任务数
if ! [[ "$MAX_JOBS" =~ ^[0-9]+$ ]] || [ "$MAX_JOBS" -lt 1 ]; then
    echo -e "${RED}错误: 并行任务数必须是大于0的整数${NC}"
    show_usage
fi

# 验证日期格式
if [[ -n "$AFTER_DATE" ]]; then
    # 验证日期格式 (YYYY-MM-DD)
    if ! [[ "$AFTER_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo -e "${RED}错误: 日期格式必须为 YYYY-MM-DD${NC}"
        show_usage
    fi
    
    # 转换为ISO 8601格式 (GitLab API要求)
    AFTER_DATE_ISO="${AFTER_DATE}T00:00:00Z"
fi

# 创建输出目录
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR" || { echo -e "${RED}错误: 无法进入输出目录${NC}"; exit 1; }

# 如果指定了日志文件，则创建
if [[ -n "$LOG_FILE" ]]; then
    touch "$LOG_FILE"
fi

# 日志函数
function log {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    if [[ -n "$LOG_FILE" ]]; then
        echo -e "[$timestamp] $1" | tee -a "$LOG_FILE"
    else
        echo -e "[$timestamp] $1"
    fi
}

log "${BLUE}=== GitLab批量克隆脚本 ===${NC}"
log "${BLUE}开始时间: $(date)${NC}"
log "${BLUE}GitLab URL: $GITLAB_URL${NC}"
log "${BLUE}输出目录: $OUTPUT_DIR${NC}"
log "${BLUE}克隆协议: $PROTOCOL${NC}"
log "${BLUE}并行任务数: $MAX_JOBS${NC}"
if [[ -n "$AFTER_DATE" ]]; then
    log "${BLUE}只克隆 $AFTER_DATE 之后更新的项目${NC}"
fi

# 如果提供了组名称，获取组ID
if [[ -n "$GROUP_NAME" && -z "$GROUP_ID" ]]; then
    log "${YELLOW}通过名称查找组ID: $GROUP_NAME${NC}"
    
    # URL编码组名称
    ENCODED_GROUP_NAME=$(echo "$GROUP_NAME" | sed 's/ /%20/g')
    
    GROUP_INFO=$(curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/groups?search=$ENCODED_GROUP_NAME")
    
    # 检查是否找到组
    if [[ "$GROUP_INFO" == "[]" ]]; then
        log "${RED}错误: 找不到名为 '$GROUP_NAME' 的组${NC}"
        exit 1
    fi
    
    # 使用jq从返回结果中提取组ID
    GROUP_ID=$(echo "$GROUP_INFO" | jq -r '.[0].id')
    
    if [[ -z "$GROUP_ID" || "$GROUP_ID" == "null" ]]; then
        log "${RED}错误: 无法获取组ID${NC}"
        exit 1
    fi
    
    log "${GREEN}找到组ID: $GROUP_ID${NC}"
fi

# 创建临时目录存储克隆任务
TEMP_DIR=$(mktemp -d)
CLONE_TASKS_FILE="$TEMP_DIR/clone_tasks.txt"
ACTIVE_JOBS_FILE="$TEMP_DIR/active_jobs.txt"
SUCCESS_COUNT_FILE="$TEMP_DIR/success_count.txt"
FAILED_COUNT_FILE="$TEMP_DIR/failed_count.txt"
touch "$CLONE_TASKS_FILE"
touch "$ACTIVE_JOBS_FILE"
echo "0" > "$SUCCESS_COUNT_FILE"
echo "0" > "$FAILED_COUNT_FILE"

# 清理函数
function cleanup {
    # 等待所有后台任务完成
    wait
    
    # 显示最终统计（先读取计数文件，再删除临时目录）
    local success_count=$(cat "$SUCCESS_COUNT_FILE" 2>/dev/null || echo "0")
    local failed_count=$(cat "$FAILED_COUNT_FILE" 2>/dev/null || echo "0")
    local total_count=$((success_count + failed_count))
    
    # 清理临时文件
    log "${YELLOW}清理临时文件...${NC}"
    rm -rf "$TEMP_DIR"
    
    log "${BLUE}=== 克隆完成 ===${NC}"
    log "${BLUE}结束时间: $(date)${NC}"
    log "${BLUE}总项目数: $total_count${NC}"
    log "${GREEN}成功克隆: $success_count${NC}"
    if [[ "$failed_count" -gt 0 ]]; then
        log "${RED}克隆失败: $failed_count${NC}"
    fi
    if [[ -n "$LOG_FILE" ]]; then
        log "${BLUE}日志文件: $LOG_FILE${NC}"
    fi
    
    exit 0
}

# 设置退出钩子
trap cleanup EXIT INT TERM

# 增加成功计数
function increment_success {
    local current=$(cat "$SUCCESS_COUNT_FILE")
    echo $((current + 1)) > "$SUCCESS_COUNT_FILE"
}

# 增加失败计数
function increment_failed {
    local current=$(cat "$FAILED_COUNT_FILE")
    echo $((current + 1)) > "$FAILED_COUNT_FILE"
}

# 获取所有子组
function get_all_subgroups {
    local parent_id=$1
    local parent_path=$2
    local page=1
    local per_page=100
    local more_pages=true
    
    while $more_pages; do
        log "${YELLOW}获取组 $parent_id 的子组 (页码: $page)...${NC}"
        
        local response=$(curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/groups/$parent_id/subgroups?page=$page&per_page=$per_page&include_subgroups=true")
        
        # 检查是否为空数组
        if [[ "$response" == "[]" ]]; then
            more_pages=false
            continue
        fi
        
        # 使用jq解析JSON响应
        echo "$response" | jq -c '.[]' | while read -r group_json; do
            local group_id=$(echo "$group_json" | jq -r '.id')
            local group_name=$(echo "$group_json" | jq -r '.name')
            local group_path=$(echo "$group_json" | jq -r '.path')
            
            local full_path="$parent_path/$group_path"
            
            log "${GREEN}发现子组: $group_name (ID: $group_id, 路径: $full_path)${NC}"
            
            # 创建子组目录
            mkdir -p "$full_path"
            
            # 获取子组中的项目
            get_projects "$group_id" "$full_path"
            
            # 递归获取子组的子组
            get_all_subgroups "$group_id" "$full_path"
        done
        
        # 检查是否有更多页
        local total_items=$(echo "$response" | jq '. | length')
        if [[ $total_items -lt $per_page ]]; then
            more_pages=false
        else
            page=$((page + 1))
        fi
    done
}

# 获取组中的项目并添加到克隆任务列表
function get_projects {
    local group_id=$1
    local output_path=$2
    local page=1
    local per_page=100
    local more_pages=true
    local api_url="$GITLAB_URL/api/v4/groups/$group_id/projects?page=$page&per_page=$per_page&include_subgroups=false"
    
    # 添加日期过滤参数
    if [[ -n "$AFTER_DATE" ]]; then
        api_url="${api_url}&updated_after=${AFTER_DATE_ISO}"
    fi
    
    while $more_pages; do
        log "${YELLOW}获取组 $group_id 的项目 (页码: $page)...${NC}"
        
        local response=$(curl -s --header "PRIVATE-TOKEN: $TOKEN" "$api_url")
        
        # 检查是否为空数组
        if [[ "$response" == "[]" ]]; then
            more_pages=false
            continue
        fi
        
        # 使用jq解析JSON响应
        echo "$response" | jq -c '.[]' | while read -r project_json; do
            local project_id=$(echo "$project_json" | jq -r '.id')
            local project_name=$(echo "$project_json" | jq -r '.name')
            local project_path=$(echo "$project_json" | jq -r '.path')
            local ssh_url=$(echo "$project_json" | jq -r '.ssh_url_to_repo')
            local http_url=$(echo "$project_json" | jq -r '.http_url_to_repo')
            local is_archived=$(echo "$project_json" | jq -r '.archived')
            local last_activity=$(echo "$project_json" | jq -r '.last_activity_at')
            
            # 如果设置了跳过已归档项目且项目已归档，则跳过
            if [[ "$SKIP_ARCHIVED" == "true" && "$is_archived" == "true" ]]; then
                log "${YELLOW}跳过已归档项目: $project_name${NC}"
                continue
            fi
            
            # 如果指定了日期过滤，再次检查最后活动时间（双重保险）
            if [[ -n "$AFTER_DATE" ]]; then
                # 将ISO日期转换为可比较的格式
                local activity_date=$(echo "$last_activity" | cut -d'T' -f1)
                
                # 比较日期
                if [[ "$activity_date" < "$AFTER_DATE" ]]; then
                    log "${YELLOW}跳过未更新项目: $project_name (最后活动: $activity_date)${NC}"
                    continue
                fi
                
                log "${GREEN}发现更新的项目: $project_name (最后活动: $activity_date)${NC}"
            else
                log "${GREEN}发现项目: $project_name (ID: $project_id)${NC}"
            fi
            
            # 选择克隆URL
            local clone_url=""
            if [[ "$PROTOCOL" == "ssh" ]]; then
                clone_url="$ssh_url"
            else
                # 对于HTTPS，添加令牌到URL
                clone_url=$(echo "$http_url" | sed "s#://#://oauth2:$TOKEN@#")
            fi
            
            # 如果目录已存在，跳过
            if [[ -d "$output_path/$project_path" ]]; then
                log "${YELLOW}目录已存在，跳过: $output_path/$project_path${NC}"
                continue
            fi
            
            # 将克隆任务添加到任务文件
            echo "$project_name|$clone_url|$output_path/$project_path|$last_activity" >> "$CLONE_TASKS_FILE"
        done
        
        # 更新API URL的页码
        page=$((page + 1))
        api_url="$GITLAB_URL/api/v4/groups/$group_id/projects?page=$page&per_page=$per_page&include_subgroups=false"
        
        # 添加日期过滤参数
        if [[ -n "$AFTER_DATE" ]]; then
            api_url="${api_url}&updated_after=${AFTER_DATE_ISO}"
        fi
        
        # 检查是否有更多页
        local total_items=$(echo "$response" | jq '. | length')
        if [[ $total_items -lt $per_page ]]; then
            more_pages=false
        else
            page=$((page + 1))
        fi
    done
}

# 并行克隆函数
function clone_project {
    local project_info=$1
    local project_name=$(echo "$project_info" | cut -d'|' -f1)
    local clone_url=$(echo "$project_info" | cut -d'|' -f2)
    local target_dir=$(echo "$project_info" | cut -d'|' -f3)
    local last_activity=$(echo "$project_info" | cut -d'|' -f4)
    local job_id=$2
    local job_log_file="$TEMP_DIR/job_${job_id}.log"
    
    # 记录作业开始
    echo "$job_id|$project_name" >> "$ACTIVE_JOBS_FILE"
    
    # 构建git clone命令
    local clone_cmd="git clone"
    
    # 添加深度参数
    if [[ -n "$CLONE_DEPTH" ]]; then
        clone_cmd="$clone_cmd --depth $CLONE_DEPTH"
    fi
    
    # 添加分支参数
    if [[ -n "$BRANCH" ]]; then
        clone_cmd="$clone_cmd --branch $BRANCH --single-branch"
    fi
    
    # 添加URL和目标目录
    clone_cmd="$clone_cmd $clone_url $target_dir"
    
    # 创建目标目录的父目录
    mkdir -p "$(dirname "$target_dir")"
    
    # 执行克隆并记录到作业日志
    # 执行克隆命令
    if eval "$clone_cmd" > "$job_log_file" 2>&1; then
        # 增加成功计数
        increment_success
        
        # 如果指定了日志文件，记录详细信息
        if [[ -n "$LOG_FILE" ]]; then
            {
                echo "开始克隆: $project_name 到 $target_dir"
                if [[ -n "$AFTER_DATE" ]]; then
                    echo "项目在 $AFTER_DATE 之后有更新 (最后活动: $(echo "$last_activity" | cut -d'T' -f1))"
                fi
                echo "命令: $clone_cmd"
                echo "开始时间: $(date)"
                echo "结束时间: $(date)"
                echo "状态: 成功"
            } >> "$LOG_FILE" 2>&1
        fi
    else
        # 增加失败计数
        increment_failed
        
        # 如果指定了日志文件，记录详细信息
        if [[ -n "$LOG_FILE" ]]; then
            {
                echo "开始克隆: $project_name 到 $target_dir"
                if [[ -n "$AFTER_DATE" ]]; then
                    echo "项目在 $AFTER_DATE 之后有更新 (最后活动: $(echo "$last_activity" | cut -d'T' -f1))"
                fi
                echo "命令: $clone_cmd"
                echo "开始时间: $(date)"
                echo "结束时间: $(date)"
                echo "状态: 失败"
                echo "错误日志:"
                cat "$job_log_file"
            } >> "$LOG_FILE" 2>&1
        fi
    fi
    
    # 从活动作业列表中移除
    # 兼容macOS和Linux的sed命令
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS
        sed -i '' "/^$job_id|/d" "$ACTIVE_JOBS_FILE"
    else
        # Linux
        sed -i "/^$job_id|/d" "$ACTIVE_JOBS_FILE"
    fi
    
    # 清理作业日志
    rm -f "$job_log_file"
}

# 任务调度器
function schedule_clone_tasks {
    local total_tasks=$(wc -l < "$CLONE_TASKS_FILE")
    local completed_tasks=0
    local job_counter=0
    
    log "${BLUE}开始并行克隆 $total_tasks 个项目，最大并行数: $MAX_JOBS${NC}"
    
    # 读取每个克隆任务
    while IFS= read -r task_line; do
        # 检查当前运行的作业数
        while [[ $(wc -l < "$ACTIVE_JOBS_FILE") -ge $MAX_JOBS ]]; do
            # 等待一个作业完成
            sleep 1
        done
        
        # 增加作业计数器
        job_counter=$((job_counter + 1))
        
        # 启动克隆作业
        clone_project "$task_line" "$job_counter" &
        
        # 增加完成任务计数
        completed_tasks=$((completed_tasks + 1))
        
        # 显示进度
        if [[ $((completed_tasks % 10)) -eq 0 || $completed_tasks -eq $total_tasks ]]; then
            log "${BLUE}进度: $completed_tasks / $total_tasks 个项目已调度${NC}"
        fi
    done < "$CLONE_TASKS_FILE"
    
    # 等待所有后台作业完成
    log "${YELLOW}等待所有克隆任务完成...${NC}"
    wait
    log "${GREEN}所有克隆任务已完成${NC}"
}

# 获取主组信息
log "${YELLOW}获取组 $GROUP_ID 的信息...${NC}"
GROUP_INFO=$(curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/groups/$GROUP_ID")

# 检查组是否存在
if [[ "$GROUP_INFO" == *"404 Not Found"* ]]; then
    log "${RED}错误: 找不到ID为 $GROUP_ID 的组${NC}"
    exit 1
fi

# 使用jq提取组路径和名称
GROUP_PATH=$(echo "$GROUP_INFO" | jq -r '.path')
GROUP_NAME=$(echo "$GROUP_INFO" | jq -r '.name')

if [[ -z "$GROUP_PATH" || "$GROUP_PATH" == "null" ]]; then
    log "${RED}错误: 无法获取组路径${NC}"
    exit 1
fi

log "${GREEN}开始处理组: $GROUP_NAME (ID: $GROUP_ID, 路径: $GROUP_PATH)${NC}"

# 创建主组目录
mkdir -p "$GROUP_PATH"

# 获取主组中的项目
get_projects "$GROUP_ID" "$GROUP_PATH"

# 获取所有子组及其项目
get_all_subgroups "$GROUP_ID" "$GROUP_PATH"

# 检查是否有项目需要克隆
if [[ ! -s "$CLONE_TASKS_FILE" ]]; then
    log "${YELLOW}没有找到需要克隆的项目${NC}"
    exit 0
fi

# 开始并行克隆任务
schedule_clone_tasks

# 脚本结束时会自动调用cleanup函数