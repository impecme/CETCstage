# 技术文档真实数据图

由 `../../scripts/generate_document_real_figures.py` 生成。该脚本只读取 `data/reports/demo/` 的正式报告和两个任务 demo 写出的 `data/generated/demo/` 输出样本，不写入或修改原始测试数据。

```bash
cd /home/usr_04/CETC
python3 ppt_work/scripts/generate_document_real_figures.py --png
```

- 图 22、图 34、图 36：只需要 `data/reports/demo/scale_summary.json`。
- 图 20、图 21、图 31—图 33：还需要任务 demo 的 `data/generated/demo/<task>/output_samples/` CSV。
- `manifest.json` 记录本次生成的文件、输入报告和缺失样本；缺失时不允许用 AI 或其他数据替代。

`scripts/performance.sh --tasks --task both --scale all` 会按 L1-L6 运行任务。图 20、图 21、图 31—图 33 的 L6 样本应在任务性能运行后直接从对应报告或输出目录取用：

```bash
sudo docker exec -it gpu_04 bash
cd /CETC
build-zx/demo/task1_radar/task1_radar_demo --repeat 5 --scale-level 6 --invalid-input-checks
build-zx/demo/task2_features/task2_features_demo --repeat 5 --scale-level 6 --invalid-input-checks
exit
sudo docker cp gpu_04:/CETC/data/generated/demo /home/usr_04/CETC/data/generated/
```
