# V4.7 第七阶段：低风险 CUDA 遗留表述收口

## 当前状态

- 状态：已完成本地低风险收口，等待按需同步到容器。
- 时间：2026-06-18。
- 进入依据：V4.6 已完成中科芯专用命名收口，Stage4 full after rename 已通过。
- 本阶段目标：继续清理不影响 ZQ500 正常运行的项目自有 CUDA 遗留表述，避免公开头文件和当前说明文档继续使用 CUDA 作为项目自有 GPU 口径。

## 本轮范围

本轮只处理不改变 ABI、报告 schema 和中科芯 SDK 兼容接口的低风险项：

- `src/zhongkexin/filtering.cu` 内部 helper：
  - `validate_cuda_window_spec` 改为 `validate_zx_gpu_window_spec`。
  - `build_cuda_window_cache_key` 改为 `build_zx_gpu_window_cache_key`。
- 公开头文件注释：
  - 将 `@brief CUDA ...` 改为 `@brief ZQ500 GPU ...`。
- 当前入口文档：
  - README 的 CPU/GPU 对照、资源漂移和目录说明改为 ZQ500 GPU 口径。
  - AGENT 的代码约定改为 ZQ500 GPU 代码约定。
- 技术图生成脚本：
  - 展示性文案从 CUDA 并行、CPU/CUDA drift、CUDA/RSS drift 改为 ZQ500/GPU 口径。
- IDE 配置：
  - 新增 `.vscode/c_cpp_properties.json` 和 `.vscode/settings.json`，让宿主机 VS Code IntelliSense 按中科芯 SDK、`dlcc`、C++17 和 CUDA-like `.cu` 语义解析源码。

## 明确不改的内容

- 不改 `cuda_runtime.h`、`cudaMalloc`、`cudaMemcpy`、`cudaDeviceSynchronize`、`cudaEvent*`。
- 不改 `cufft*`、`cublas*`、`cusolver*`。
- 不改 `.cu` 源文件后缀。
- 不改 `dlcc -x cuda --cuda-gpu-arch=dlgput64`。
- 不改 demo/report JSON 字段中的 `cuda_free_mib`、`cuda_total_mib`、`cuda_device_name`、`cuda_free_drift_mib`。
- 不把 VS Code IntelliSense 配置作为真实构建入口；真实验收仍以容器内 Stage 脚本为准。

上述内容要么是中科芯 SDK 兼容 ABI/API，要么是已有报告 schema。尤其是 `cuda_*` 报告字段虽然可以继续改名，但需要同步 demo、汇总、绘图和历史报告兼容策略，必须单独作为下一轮 schema 迁移处理。

## 验证要求

- 本地静态扫描确认当前入口中项目自有旧 helper 名不再出现。
- `python3 -m py_compile` 检查技术图脚本。
- `python3 -m json.tool` 检查 VS Code JSON 配置。
- `git diff --check` 检查本轮修改。
- 本轮没有改算法、构建、SDK 符号或报告 schema，不要求单独触发 Stage4 full；下一次容器全量复验可随 schema 迁移或提交前维护性复验一起执行。

## 完成判定

- 公开头文件不再用 `CUDA ... 返回结果` 描述 ZQ500 GPU 类型。
- README/AGENT 当前入口说明不再把项目 GPU 链路描述为 CUDA 链路。
- 技术图脚本文案不再将当前并行策略命名为 CUDA 策略。
- 中科芯 SDK 兼容符号和已通过的 ZQ500 运行链路保持不变。
