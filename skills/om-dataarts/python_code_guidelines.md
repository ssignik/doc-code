# Python 编码规范指南 Skill

## 用途
编写符合规范的 Python 代码，避免常见的代码质量问题。

## 触发条件
- 编写 Python 代码时
- 代码审查时
- 用户询问 Python 编码规范

---

## 核心规范

### 1. 资源管理 (G.PRM.03)

**原则**: 资源的申请和释放需要成对使用，包括正常和异常场景。

**最佳实践**:
```python
# 文件操作 - 使用 with 语句
with open(file_path, encoding="UTF-8") as f:
    data = yaml.safe_load(f)

# 数据库连接 - 使用上下文管理器
with self.get_cursor() as cursor:
    cursor.execute(query)

# 网络请求 - 使用 with 语句
with requests.Session() as session:
    response = session.get(url)
```

**避免**:
```python
# 错误: 文件未关闭
f = open(file_path)
data = f.read()
# 忘记 f.close()
```

---

### 2. 函数返回值一致性 (G.CTL.01)

**原则**: 同一个函数所有分支的返回值类型和个数保持一致。

**最佳实践**:
```python
def get_user(self, user_id: str) -> Optional[Dict]:
    """获取用户信息"""
    if not user_id:
        return None  # 明确返回 None

    user = self.db.query(user_id)
    if not user:
        return None  # 统一返回 None

    return user  # 返回用户数据

def calculate(self, data: List) -> Tuple[int, int]:
    """计算结果"""
    if not data:
        return 0, 0  # 返回默认元组

    total = sum(data)
    count = len(data)
    return total, count  # 返回相同格式的元组
```

**避免**:
```python
# 错误: 返回值不一致
def get_data(self, id):
    if not id:
        return  # 隐式返回 None
    return self.query(id)  # 返回数据
```

---

### 3. 参数默认值 (G.FNM.01)

**原则**: 禁止使用可变对象作为参数默认值。

**最佳实践**:
```python
# 正确: 使用 None 作为默认值
def process_items(self, items=None):
    if items is None:
        items = []
    items.append("new")
    return items

def update_config(self, config=None):
    if config is None:
        config = {}
    config["updated"] = True
    return config
```

**避免**:
```python
# 错误: 可变默认值会在调用间共享
def process_items(self, items=[]):
    items.append("new")
    return items

# 调用多次会累积数据
obj.process_items()  # ["new"]
obj.process_items()  # ["new", "new"] - 意外的行为
```

---

### 4. 变量命名 (G.VAR.03)

**原则**: 禁止覆盖外部作用域中的标识符。

**最佳实践**:
```python
import json

def process(self, data):
    # 使用不同的变量名避免冲突
    json_data = data.get("json")
    json_str = json.dumps(json_data)  # json 模块仍然可用
    return json_str
```

**常见冲突变量名**:
- `json` - JSON 模块
- `list` - 内置函数
- `dict` - 内置函数
- `str` - 内置类型
- `type` - 内置函数
- `id` - 内置函数
- `input` - 内置函数
- `format` - 内置函数
- `open` - 内置函数

---

### 5. 测试资源清理 (G.FIO.04)

**原则**: 临时文件使用完毕应及时删除。

**最佳实践**:
```python
import unittest
import tempfile
import shutil

class TestExample(unittest.TestCase):
    def setUp(self):
        # 创建临时目录
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        # 清理临时目录
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_something(self):
        # 使用临时目录
        test_file = os.path.join(self.temp_dir, "test.txt")
        with open(test_file, "w") as f:
            f.write("test")
        # tearDown 会自动清理
```

---

### 6. 异常处理 (G.ERR.09, G.ERR.05)

**原则**:
- 禁止在单个 except 代码块内重复捕获同类异常
- 使用有明确业务属性的异常类型

**最佳实践**:
```python
# 正确: 分别捕获不同异常
try:
    data = json.loads(content)
except json.JSONDecodeError as e:
    logger.error(f"JSON 解析失败: {e}")
    raise ValueError("无效的 JSON 格式")
except KeyError as e:
    logger.error(f"缺少必要字段: {e}")
    raise ValueError("数据格式不完整")

# 正确: 明确异常类型
try:
    response = requests.get(url, timeout=30)
except requests.Timeout:
    logger.error("请求超时")
    raise ConnectionError("服务不可用")
except requests.RequestException as e:
    logger.error(f"请求失败: {e}")
    raise
```

**避免**:
```python
# 错误: 裸 except 捕获所有异常
try:
    func()
except:  # 会捕获 KeyboardInterrupt, SystemExit 等
    pass

# 错误: 重复捕获父子异常
try:
    func()
except (ValueError, Exception):  # Exception 已包含 ValueError
    pass
```

---

### 7. 命令执行 (G.EDV.04)

**原则**: 禁止使用 subprocess 模块中的 shell=True 选项。

**最佳实践**:
```python
import subprocess

# 正确: 使用列表形式传递命令
result = subprocess.run(
    ["git", "log", "-p", file_path],
    capture_output=True,
    text=True
)

# 正确: Popen 使用列表
process = subprocess.Popen(
    ["git", "clone", repo_url],
    stdout=subprocess.PIPE,
    cwd=work_dir
)
```

**避免**:
```python
# 错误: shell=True 存在命令注入风险
file_path = "test; rm -rf /"
subprocess.run(f"cat {file_path}", shell=True)  # 危险!

# 正确: 即使需要 shell 功能，也要避免
subprocess.run(["cat", file_path])
```

---

## 快速检查清单

编写代码时，请检查以下项目:

- [ ] 文件操作是否使用 `with` 语句?
- [ ] 函数所有分支是否都有明确的返回值?
- [ ] 参数默认值是否使用了可变对象 (`[]`, `{}`)?
- [ ] 变量名是否与导入的模块或内置函数冲突?
- [ ] 测试中临时文件是否有 `tearDown` 清理?
- [ ] 异常捕获是否指定了明确的类型?
- [ ] subprocess 是否避免了 `shell=True`?

## 相关工具配置

### .pylintrc 配置
```ini
[MESSAGES CONTROL]
enable=
    inconsistent-return-statements,
    dangerous-default-value,
    redefined-outer-name,
    bare-except

[FORMAT]
max-line-length=120
```

### pre-commit 配置
```yaml
repos:
  - repo: https://github.com/pycqa/pylint
    rev: v2.17.0
    hooks:
      - id: pylint
        args:
          - --disable=all
          - --enable=inconsistent-return-statements,dangerous-default-value,redefined-outer-name,bare-except
```

## 相关 Skill
- `code_quality_check.md` - 代码质量检查工具