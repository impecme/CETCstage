# ZQ500 平台兼容矩阵摘要

本文件由 `scripts/platform/generate_zx_compat_matrix.py` 从三个复赛 XLSX 表生成。
完整逐行矩阵位于 `data/reports/zhongkexin/v5_2_compatibility/`。

## 覆盖结果

- 非空源行：`900`。
- API 行：`816`。
- 唯一 API：`830`。
- 明确禁止 API：`315`。
- Driver/Runtime/科学库源行：`361` / `278` / `261`。

## 状态口径

- `supported`：进入安全运行探针。
- `partial`：记录限制并在边界探针中验证。
- `unsupported`：API 行进入项目禁止引用扫描。
- 设备复位、跨设备、IPC、外部资源等高影响 API 仅编译验证。
- 科学库某数据类型或参数形态不支持时，整行记为 `partial`；只有明确点名的不可用 API 才进入禁止清单。

本摘要仅证明源表解析和分类完成。探针状态将在 V5.2-06 更新，不代表当前项目已通过全部兼容性验证。
