# Task Demo Scale Benchmark

- pass: `true`
- repeat: `3`

| task | scale | size | validation | gpu_ms | cpu_ms | speedup | max_mixed_error | jitter | cuda_drift_mib | rss_drift_mib |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| task1_radar | L1 | 32x128 | true | 2.802120 | 1.886000 | 0.673 | 0.000278533 | 0.000324875 | 0 | 0 |
| task2_features | L1 | 16x512 | true | 30.252800 | 122.344000 | 4.044 | 0.00393563 | 0.00848028 | 0 | 0.316406 |
| task1_radar | L2 | 48x256 | true | 2.294870 | 5.012750 | 2.184 | 0.00211334 | 0.00120197 | 0 | 0 |
| task2_features | L2 | 32x768 | true | 71.736400 | 414.067000 | 5.772 | 0.00523943 | 0.102898 | 0 | 0.0507812 |
| task1_radar | L3 | 64x256 | true | 2.473180 | 5.322800 | 2.152 | 0.00248718 | 0.0244029 | 0 | 0 |
| task2_features | L3 | 48x1024 | true | 124.562000 | 879.592000 | 7.061 | 0.0031292 | 0.0106346 | 0 | 0.339844 |
| task1_radar | L4 | 96x512 | true | 2.587820 | 15.514600 | 5.995 | 0.0208969 | 0.00204645 | 0 | 0.289062 |
| task2_features | L4 | 64x1536 | true | 155.302000 | 2057.250000 | 13.247 | 0.00308792 | 0.00215331 | 0 | 0.640625 |
| task1_radar | L5 | 128x1024 | true | 3.701480 | 34.023600 | 9.192 | 0.0544498 | 0.00495638 | 0 | 0.96875 |
| task2_features | L5 | 80x2048 | true | 257.566000 | 4101.200000 | 15.923 | 0.00206816 | 0.0167719 | 0 | 1.22656 |
| task1_radar | L6 | 192x1536 | true | 7.411250 | 83.343900 | 11.246 | 0.335136 | 0.00222598 | 0 | 5.73438 |
| task2_features | L6 | 96x3072 | true | 416.474000 | 8779.350000 | 21.080 | 0.000853242 | 0.0305265 | 0 | 3.07422 |

## Artifacts

- scale csv: `data/reports/demo/latest_task_demo_scale_benchmark.csv`
- scale json: `data/reports/demo/latest_task_demo_scale_report.json`
- scale markdown: `data/reports/demo/latest_task_demo_scale_report.md`
