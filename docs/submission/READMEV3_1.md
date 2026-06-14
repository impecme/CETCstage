# V3.1 `task1_radar` 任务级 Demo 与 Python 可视化

## 版本信息

- 版本名称：`V3.1 task1_radar 任务级 Demo 与 Python 可视化`
- 完成时间：`2026-04-14`
- 创建者：`CICC1001212非诚勿扰`

## 本轮新增

- 新增 `demo/task1_radar/` 正式任务级入口
- 新增 `task1_radar_demo`：
  - 单目标回波模拟
  - 脉冲压缩
  - 多普勒处理
  - CA-CFAR 检测
  - 模糊函数分析
- 新增 `visualize_task1.py`：
  - 读取 demo 生成的 CSV/JSON
  - 输出任务一完整图表 PNG

## 输出内容

- `latest_summary.md`
- `latest_metrics.json`
- `latest_stage_timings.csv`
- `figures/*.png`

## 运行方式

```bash
./scripts/build/build_v1.sh
./build/demo/task1_radar/task1_radar_demo
python3 demo/task1_radar/visualize_task1.py
```

## 依赖说明

- C++ / CUDA demo：沿用仓库现有构建依赖
- Python 可视化：`python3`、`numpy`、`matplotlib`
