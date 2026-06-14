# V3.2 `task2_features` 任务级 Demo 与 Python 可视化

## 版本信息

- 版本名称：`V3.2 task2_features 任务级 Demo 与 Python 可视化`
- 完成时间：`2026-04-14`

## 本轮新增

- 新增 `demo/task2_features/`
- 新增 `task2_features_demo`
- 新增 `visualize_task2.py`
- 新增任务二的 CSV / JSON / Markdown / PNG 输出链路

## 输出内容

- `latest_summary.md`
- `latest_metrics.json`
- `latest_stage_timings.csv`
- `figures/*.png`

## 运行方式

```bash
./scripts/build/build_v1.sh
./build/demo/task2_features/task2_features_demo
python3 demo/task2_features/visualize_task2.py
```

## 依赖说明

- C++ / CUDA demo：沿用仓库现有构建依赖
- Python 可视化：`python3`、`numpy`、`matplotlib`
