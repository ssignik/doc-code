# Python 代码质量检查 Skill

## 用途
检查 Python 代码中的常见质量问题，确保代码符合规范。

## 触发条件
- 用户提到"代码检查"、"代码质量"、"lint"、"pylint"
- 提交代码前检查
- CI/CD 流水线检查

## 检查规则

### 1. G.PRM.03 - 资源申请和释放成对使用
**问题**: 文件打开后没有关闭
**检测方法**:
```bash
# 搜索未使用 with 语句的 open() 调用
grep -n "open(" --include="*.py" | grep -v "with open"
```

**错误示例**:
```python
# 错误: 文件未关闭
data = yaml.safe_load(open(file_path))
```

**正确示例**:
```python
# 正确: 使用 with 语句自动关闭
with open(file_path) as f:
    data = yaml.safe_load(f)
```

---

### 2. G.CTL.01 - 函数返回值一致性
**问题**: 同一个函数所有分支的返回值类型和个数不一致
**检测方法**:
```bash
# 使用 pylint 检测
pylint --disable=all --enable=inconsistent-return-statements <file>
```

**错误示例**:
```python
def get_data(self, id):
    if not id:
        return  # 没有返回值
    return self.query(id)  # 有返回值
```

**正确示例**:
```python
def get_data(self, id):
    if not id:
        return None  # 统一返回 None
    return self.query(id)
```

---

### 3. G.FNM.01 - 禁止可变对象作为参数默认值
**问题**: 使用 `[]` 或 `{}` 作为参数默认值
**检测方法**:
```bash
# 搜索可变默认参数
grep -n "def.*\[\]" --include="*.py"
grep -n "def.*{}" --include="*.py"
```

**错误示例**:
```python
def process_items(self, items=[]):
    items.append("new")
    return items
```

**正确示例**:
```python
def process_items(self, items=None):
    if items is None:
        items = []
    items.append("new")
    return items
```

---

### 4. G.VAR.03 - 禁止覆盖外部作用域标识符
**问题**: 局部变量名与外部作用域变量名冲突
**检测方法**:
```bash
# 使用 pylint 检测
pylint --disable=all --enable=redefined-outer-name <file>
```

**错误示例**:
```python
import json

def process(self, data):
    json = data.get("json")  # 覆盖了导入的 json 模块
    return json
```

**正确示例**:
```python
import json

def process(self, data):
    json_data = data.get("json")  # 使用不同的变量名
    return json_data
```

---

### 5. G.FIO.04 - 临时文件及时删除
**问题**: 测试中创建的临时文件/目录未清理
**检测方法**:
```bash
# 检查测试文件中的 tearDown 方法
grep -n "tearDown" tests/**/*.py
```

**错误示例**:
```python
class TestExample(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
    # 缺少 tearDown 方法
```

**正确示例**:
```python
class TestExample(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)
```

---

### 6. G.ERR.09 - 禁止重复捕获同类异常
**问题**: 同时捕获父子异常类
**检测方法**:
```bash
# 使用 pylint 检测
pylint --disable=all --enable=duplicate-except <file>
```

**错误示例**:
```python
try:
    func()
except (ValueError, Exception):  # Exception 是 ValueError 的父类
    pass
```

**正确示例**:
```python
try:
    func()
except ValueError:
    pass
except Exception:
    pass
```

---

### 7. G.EDV.04 - 禁止使用 shell=True
**问题**: subprocess 模块中使用 shell=True 存在命令注入风险
**检测方法**:
```bash
grep -n "shell=True" --include="*.py"
```

**错误示例**:
```python
subprocess.Popen(f"git log -p {path}", shell=True)
```

**正确示例**:
```python
subprocess.Popen(["git", "log", "-p", path])
```

---

### 8. G.ERR.05 - 使用明确的异常类型
**问题**: 使用裸 `except:` 捕获所有异常
**检测方法**:
```bash
grep -n "except:" --include="*.py" | grep -v "except Exception"
```

**错误示例**:
```python
try:
    func()
except:  # 捕获所有异常，包括 KeyboardInterrupt
    pass
```

**正确示例**:
```python
try:
    func()
except Exception:  # 明确指定异常类型
    pass
```

## 检查命令汇总

```bash
# 运行完整检查
pylint --rcfile=.pylintrc src/

# 或使用以下脚本快速检查
pylint --disable=all \
  --enable=inconsistent-return-statements,\
redefined-outer-name,\
dangerous-default-value,\
bare-except,\
duplicate-except \
  src/
```

## 相关工具
- **pylint**: Python 代码静态分析
- **flake8**: 代码风格检查
- **ruff**: 快速 Python linter

## 相关 Skill
- `python_code_guidelines.md` - Python 编码规范指南