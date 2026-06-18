# READMEV4_7

## 版本目标

V4.7 在 V4.6 完成中科芯专用命名收口后，继续清理低风险 CUDA 遗留表述。本轮不改算法、不改构建入口、不改中科芯 SDK 兼容接口、不改报告 JSON 字段，只处理内部 helper 名和展示性文案。

## 核心改动

- `src/zhongkexin/filtering.cu` 内部 helper 从 `validate_cuda_window_spec` / `build_cuda_window_cache_key` 改为 `validate_zx_gpu_window_spec` / `build_zx_gpu_window_cache_key`。
- 公开头文件中 `@brief CUDA ...` 改为 `@brief ZQ500 GPU ...`。
- README 和 AGENT 的当前口径改为 CPU reference + ZQ500 GPU。
- 技术图生成脚本中的 CUDA 并行、CPU/CUDA drift、CUDA/RSS drift 展示文案改为 ZQ500/GPU 口径。
- 新增 VS Code C/C++ IntelliSense 配置，指定宿主机中科芯 SDK include、`dlcc`、C++17 和 `.cu` 文件关联，减少 `std::get_if`、kernel launch 和 `__cudaPushCallConfiguration` 误报。

## 保留内容

以下内容不是可删除遗留，而是中科芯 SDK 当前接口或既有报告 schema：

- `cuda_runtime.h`、`cudaMalloc`、`cudaMemcpy`、`cudaDeviceSynchronize`、`cudaEvent*`
- `cufft*`、`cublas*`、`cusolver*`
- `.cu` 源文件后缀
- `dlcc -x cuda --cuda-gpu-arch=dlgput64`
- demo/report 字段 `cuda_free_mib`、`cuda_total_mib`、`cuda_device_name`、`cuda_free_drift_mib`

## 验证状态

本轮按静态修改关闭。由于没有改变算法、构建、SDK ABI/API 或报告 schema，V4.6 的 Stage4 full after rename 仍是当前完整功能基线。后续若迁移 `cuda_*` 报告字段，需要单独执行报告 schema 迁移并重新跑 Stage4 full。

补充校验：

- `.vscode/c_cpp_properties.json` 和 `.vscode/settings.json` 已通过 `python3 -m json.tool`。
- 配置引用的 `/home/usr_04/zq500_sdk_full/bin/dlcc`、`cuda_runtime.h` 和 clang CUDA wrapper 均存在。
