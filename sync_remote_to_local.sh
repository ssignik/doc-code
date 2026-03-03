#!/bin/bash
# ============================================================
# 远程 PG 数据库结构 + 少量数据同步到本地脚本
# 用法:
#   ./sync_remote_to_local.sh -h <host> -p <port> -U <user> -W <password> -d <dbname> [-s <schema>] [-n <limit>]
# ============================================================

set -e

# ---------- 本地数据库配置（已预填）----------
LOCAL_HOST="localhost"
LOCAL_PORT="5432"
LOCAL_USER="postgres"
LOCAL_DB="onedata"
LOCAL_PASSWORD="onedata"

# ---------- 解析命令行参数 ----------
REMOTE_HOST=""
REMOTE_PORT="5432"
REMOTE_USER=""
REMOTE_PASSWORD=""
REMOTE_DB=""
SCHEMA="public"
LIMIT=100

usage() {
    echo "用法: $0 -h <host> -p <port> -U <user> -W <password> -d <dbname> [-s <schema>] [-n <limit>]"
    echo "  -h  远程数据库 host（必填）"
    echo "  -p  远程数据库 port（默认 5432）"
    echo "  -U  远程数据库用户名（必填）"
    echo "  -W  远程数据库密码（必填）"
    echo "  -d  远程数据库名（必填）"
    echo "  -s  要同步的 schema（默认 public）"
    echo "  -n  每表最多同步行数（默认 100）"
    exit 1
}

while getopts "h:p:U:W:d:s:n:" opt; do
    case $opt in
        h) REMOTE_HOST="$OPTARG" ;;
        p) REMOTE_PORT="$OPTARG" ;;
        U) REMOTE_USER="$OPTARG" ;;
        W) REMOTE_PASSWORD="$OPTARG" ;;
        d) REMOTE_DB="$OPTARG" ;;
        s) SCHEMA="$OPTARG" ;;
        n) LIMIT="$OPTARG" ;;
        *) usage ;;
    esac
done

if [[ -z "$REMOTE_HOST" || -z "$REMOTE_USER" || -z "$REMOTE_DB" ]]; then
    echo "错误: -h, -U, -d 为必填参数"
    usage
fi

# 远程密码：-W 优先，否则继承环境变量 PGPASSWORD
REMOTE_PASSWORD="${REMOTE_PASSWORD:-${PGPASSWORD:-}}"

# 参数解析完毕，后续不再全局 exit on error
set +e

echo "============================================================"
echo "远程数据库: $REMOTE_USER@$REMOTE_HOST:$REMOTE_PORT/$REMOTE_DB (schema: $SCHEMA)"
echo "本地数据库: $LOCAL_USER@$LOCAL_HOST:$LOCAL_PORT/$LOCAL_DB"
echo "每表最多同步: $LIMIT 条"
echo "============================================================"

# ── 远程 psql 快捷函数 ──────────────────────────────────────────
remote_psql() {
    PGPASSWORD="$REMOTE_PASSWORD" psql -h "$REMOTE_HOST" -p "$REMOTE_PORT" -U "$REMOTE_USER" -d "$REMOTE_DB" "$@"
}
local_psql() {
    PGPASSWORD="$LOCAL_PASSWORD" psql -h "$LOCAL_HOST" -p "$LOCAL_PORT" -U "$LOCAL_USER" -d "$LOCAL_DB" "$@"
}

# ---------- Step 0: 查出有/无权限的表 ----------
echo ""
echo "[0/3] 检查远程表访问权限..."

# 有权限的表
ACCESSIBLE_TABLES=$(remote_psql -t -A -c "
    SELECT tablename
    FROM pg_tables
    WHERE schemaname = '$SCHEMA'
      AND has_table_privilege(current_user, schemaname||'.'||tablename, 'SELECT')
    ORDER BY tablename" 2>/dev/null)

ACCESSIBLE_COUNT=$(echo "$ACCESSIBLE_TABLES" | grep -c . || true)

# 无权限的表（用于统计展示）
NO_PERM_COUNT=$(remote_psql -t -A -c "
    SELECT COUNT(*)
    FROM pg_tables
    WHERE schemaname = '$SCHEMA'
      AND NOT has_table_privilege(current_user, schemaname||'.'||tablename, 'SELECT')" \
    2>/dev/null || echo "?")

echo "      可访问: $ACCESSIBLE_COUNT 张表 | 无权限跳过: $NO_PERM_COUNT 张表"

if [[ -z "$ACCESSIBLE_TABLES" ]]; then
    echo "      ❌ 没有可访问的表，请检查远程连接和权限"
    exit 1
fi

# ---------- Step 1: 只对有权限的表做 Schema 导出 ----------
echo ""
echo "[1/3] 正在导出远程数据库结构（仅有权限的表）..."

SCHEMA_FILE="/tmp/remote_schema_$$.sql"

# 用 bash 数组存 -t 参数，避免字符串拼接的展开问题
TABLE_ARGS=()
while IFS= read -r T; do
    [[ -n "$T" ]] && TABLE_ARGS+=(-t "$T")
done <<< "$ACCESSIBLE_TABLES"

PG_DUMP_ERR=$(PGPASSWORD="$REMOTE_PASSWORD" pg_dump \
    -h "$REMOTE_HOST" \
    -p "$REMOTE_PORT" \
    -U "$REMOTE_USER" \
    -d "$REMOTE_DB" \
    -n "$SCHEMA" \
    --schema-only \
    --no-owner \
    --no-privileges \
    "${TABLE_ARGS[@]}" \
    -f "$SCHEMA_FILE" 2>&1)
PG_DUMP_EXIT=$?

if [[ $PG_DUMP_EXIT -ne 0 ]]; then
    echo "      ❌ Schema 导出失败，pg_dump 报错如下："
    echo "$PG_DUMP_ERR" | sed 's/^/      /'
    rm -f "$SCHEMA_FILE"
    exit 1
fi

echo "      Schema 已导出（共 $ACCESSIBLE_COUNT 张表）"

# ---------- Step 2: 导入 Schema 到本地 ----------
echo ""
echo "[2/3] 正在将结构导入本地数据库..."

local_psql \
    -c "SET session_replication_role = replica;" \
    -f "$SCHEMA_FILE" \
    -c "SET session_replication_role = DEFAULT;" \
    2>&1 | grep -Ev "^(SET|$)" || true

echo "      结构导入完成"

# ---------- Step 3: 逐表同步数据 ----------
echo ""
echo "[3/3] 正在同步各表数据（每表最多 $LIMIT 条）..."

SUCCESS=0
FAILED=0
SKIPPED_EMPTY=0

local_psql -c "SET session_replication_role = replica;" > /dev/null 2>&1

while IFS= read -r TABLE; do
    [[ -z "$TABLE" ]] && continue

    # 检查远程表是否有数据
    ROW_COUNT=$(remote_psql -t -A \
        -c "SELECT COUNT(*) FROM \"$SCHEMA\".\"$TABLE\" LIMIT 1" 2>/dev/null)

    if [[ -z "$ROW_COUNT" || "$ROW_COUNT" == "0" ]]; then
        echo "  [跳过] $TABLE（空表）"
        ((SKIPPED_EMPTY++))
        continue
    fi

    echo -n "  [同步] $TABLE ... "

    remote_psql \
        -c "\COPY (SELECT * FROM \"$SCHEMA\".\"$TABLE\" LIMIT $LIMIT) TO STDOUT WITH (FORMAT CSV, HEADER false, NULL '\N')" \
        2>/dev/null \
    | local_psql \
        -c "\COPY \"$SCHEMA\".\"$TABLE\" FROM STDIN WITH (FORMAT CSV, HEADER false, NULL '\N')" \
        > /dev/null 2>&1

    PIPE_STATUS=("${PIPESTATUS[@]}")
    if [[ ${PIPE_STATUS[0]} -eq 0 && ${PIPE_STATUS[1]} -eq 0 ]]; then
        echo "OK"
        ((SUCCESS++))
    else
        echo "FAILED（已跳过）"
        ((FAILED++))
    fi

done <<< "$ACCESSIBLE_TABLES"

local_psql -c "SET session_replication_role = DEFAULT;" > /dev/null 2>&1

# ---------- 清理 & 汇总 ----------
rm -f "$SCHEMA_FILE"

echo ""
echo "============================================================"
echo "同步完成:"
echo "  ✅ 成功同步:   $SUCCESS 张表"
echo "  ⚠️  无权限跳过: $NO_PERM_COUNT 张表"
echo "  ⬜ 空表跳过:   $SKIPPED_EMPTY 张表"
echo "  ❌ 其他失败:   $FAILED 张表"
echo "============================================================"
