# Magic-API 接口识别 Skill

## 数据来源
接口元数据存储在 PostgreSQL `onedata` 库的 `magic_api_file_v2` 表：
```sql
-- 查看所有接口
SELECT file_path, file_content FROM magic_api_file_v2;
```

表结构：
| 列 | 说明 |
|----|------|
| `file_path` | 虚拟文件路径，如 `/magic-api/api/指标字典/Dict总数.ms` |
| `file_content` | JSON 字符串，内容因文件类型不同而异 |

---

## 文件类型识别

### 1. `group.json` — 接口分组（目录）
路径规律：`/magic-api/api/{分组名}/group.json`

```json
{
  "id": "709908d8728741d19dd2d28b98d0e23a",
  "name": "指标字典",
  "type": "api",
  "parentId": "0",
  "path": "dict"
}
```

| 字段 | 含义 |
|------|------|
| `id` | 分组唯一 ID，供 .ms 文件引用 |
| `name` | 分组展示名 |
| `path` | API 第一层路径前缀，如 `dict` |
| `parentId` | `"0"` 表示顶级，非 `"0"` 表示子分组 |

### 2. `.ms` 文件 — 具体 API 接口
路径规律：`/magic-api/api/{分组名}/{接口名}.ms`

`file_content` 是 JSON + `================================` 分隔符 + MagicScript 脚本，分两段存储：

```
{ ...JSON元数据... }
================================
var name = body.name
...脚本实现...
```

---

## .ms 文件 JSON 元数据字段

```json
{
  "id": "copy1745506310457d18777",
  "groupId": "709908d8728741d19dd2d28b98d0e23a",
  "name": "Dict总数",
  "path": "/total",
  "method": "POST",
  "parameters": [...],
  "requestBody": "...",
  "responseBody": "...",
  "description": null
}
```

| 字段 | 含义 |
|------|------|
| `groupId` | 关联 group.json 的 id |
| `name` | 接口展示名 |
| `path` | 接口自身路径，如 `/total` |
| `method` | HTTP 方法：GET / POST / PUT / DELETE |
| `parameters` | Query 参数列表（见下） |
| `requestBody` | 请求 Body 示例（JSON 字符串） |
| `responseBody` | 响应示例（JSON 字符串） |
| `description` | 接口描述 |

**全路径拼接规则：**
```
完整 API 路径 = group.path + endpoint.path
示例: "dict" + "/total" = "dict/total"
调用地址: POST /magic-api/dict/total
```

### parameters 字段结构
```json
{
  "name": "metric",
  "required": false,
  "dataType": "String",
  "description": null,
  "defaultValue": null
}
```

---

## MagicScript 脚本解析（`====` 之后）

脚本是 Groovy-like 语言，支持 MyBatis 动态 SQL XML 标签。

### 常用变量
| 变量 | 来源 |
|------|------|
| `body.xxx` | POST 请求 Body 中的字段 |
| `param.xxx` | Query 参数 |
| `header.xxx` | 请求 Header |

### 动态 SQL 标签
```xml
<if test="x != null">...</if>
<elseif test="...">...</elseif>
<else>...</else>
<foreach collection="list" item="item" separator="," open="(" close=")">
    #{item}
</foreach>
```

### 变量插值
| 语法 | 用途 |
|------|------|
| `${column}` | 直接插入（列名等，不转义） |
| `#{value}` | 参数绑定（防 SQL 注入） |
| `'%${value}%'` | LIKE 模糊匹配 |

### 数据库操作
```groovy
db.select(sqlstr)          // 查询多行，返回 List
db.select(sqlstr)[0]       // 取第一行
db.insert(sqlstr)          // 插入
db.update(sqlstr)          // 更新
db.delete(sqlstr)          // 删除
db.page(sqlstr)            // 分页查询
```

### 返回格式（固定）
```json
{
  "code": 1,
  "message": "success",
  "data": { ... },
  "timestamp": 1745507651806
}
```

---

## 典型接口模式

### 模式 1：总数查询（count）
- 路径：`xxx/total`
- Body：`{ "filters": [...], "name": "表名" }`
- SQL：`SELECT count(1) FROM {table} WHERE ...动态条件...`
- 返回：`{ "data": { "count": 211 } }`

### 模式 2：列表查询（list）
- 路径：`xxx/list`
- Body：`{ "filters": [...], "name": "表名", "order_field": "...", "order_dir": "asc" }`
- SQL：`SELECT * FROM {table} WHERE ...ORDER BY... LIMIT ...`
- 返回：`{ "data": [...] }`

### 模式 3：分页查询（page）
- 路径：`xxx/page`
- Body：`{ "page": 1, "pageSize": 10, "filters": [...] }`
- 使用 `db.page(sqlstr)`
- 返回：`{ "data": { "total": 100, "list": [...] } }`

### filters 通用结构
```json
{
  "filters": [
    { "column": "user_login", "operator": "=",    "value": "xxx" },
    { "column": "name",       "operator": "like",  "value": "key" },
    { "column": "status",     "operator": "in",    "value": ["a","b"] }
  ]
}
```

支持的 operator：`=`、`!=`、`>`、`<`、`>=`、`<=`、`like`、`left_like`、`right_like`、`in`

---

## 从数据库读取并解析接口的 Python 方法

```python
import json
import psycopg2
import psycopg2.extras

def load_magic_apis():
    conn = psycopg2.connect(host="localhost", port=5432,
                            dbname="onedata", user="postgres", password="onedata")
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT file_path, file_content FROM magic_api_file_v2")
    rows = cur.fetchall()
    conn.close()

    groups = {}   # group_id -> {name, path}
    endpoints = []

    for row in rows:
        path = row["file_path"]
        content = row["file_content"] or ""

        if path.endswith("group.json"):
            # 分隔符前是 JSON
            json_part = content.split("================================")[0].strip()
            meta = json.loads(json_part)
            groups[meta["id"]] = {"name": meta["name"], "path": meta["path"]}

        elif path.endswith(".ms"):
            parts = content.split("================================", 1)
            meta = json.loads(parts[0].strip())
            script = parts[1].strip() if len(parts) > 1 else ""
            meta["_script"] = script
            endpoints.append(meta)

    # 拼接完整路径
    for ep in endpoints:
        group = groups.get(ep.get("groupId"), {})
        ep["_full_path"] = f"{group.get('path', '')}{ep.get('path', '')}"
        ep["_group_name"] = group.get("name", "")

    return groups, endpoints
```

---

## 前端识别接口的约定

读取到接口后，前端调用格式：
```
{method} /magic-api/{_full_path}
Content-Type: application/json
Body: {requestBody 示例}
```

响应固定结构：
```json
{ "code": 1, "message": "success", "data": <实际数据> }
```

前端判断成功：`response.code === 1`

---

## 后端生成接口的规则

根据 `.ms` 元数据自动生成 FastAPI/Spring 接口时：
1. `method` → HTTP 方法
2. `_full_path` → 路由路径
3. `parameters` → Query 参数定义
4. `requestBody` 示例 → Request Body Schema
5. `responseBody` 示例 → Response Schema
6. `_script` 中的 SQL → 实际数据库查询逻辑（提取 FROM 后的表名和动态条件）