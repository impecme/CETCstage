# Task Demo Scale Benchmark

- pass: `true`
- repeat: `3`

| task | scale | size | validation | gpu_ms | cpu_ms | speedup | max_mixed_error | jitter | cuda_drift_mib | rss_drift_mib |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| task1_radar | L1 | 32x128 | true | 2.099860 | 1.879210 | 0.895 | 0.000278533 | 0.00366603 | 0 | 0 |
| task2_features | L1 | 16x512 | true | 29.499200 | 122.068000 | 4.138 | 0.00393563 | 0.00140731 | 0 | 0.253906 |
| task1_radar | L2 | 48x256 | true | 2.247430 | 4.977370 | 2.215 | 0.00211334 | 0.00166469 | 0 | 0 |
| task2_features | L2 | 32x768 | true | 72.507000 | 450.075000 | 6.207 | 0.00523943 | 0.0762277 | 0 | 0.0507812 |
| task1_radar | L3 | 64x256 | true | 2.156020 | 5.315750 | 2.466 | 0.00248718 | 0.00954776 | 0 | 0 |
| task2_features | L3 | 48x1024 | true | 121.443000 | 880.885000 | 7.253 | 0.0031292 | 0.00375579 | 0 | 0.367188 |
| task1_radar | L4 | 96x512 | true | 2.609170 | 15.392100 | 5.899 | 0.0208969 | 0.000441182 | 0 | 0.542969 |
| task2_features | L4 | 64x1536 | true | 184.513000 | 2072.530000 | 11.232 | 0.00308792 | 1.34799e-05 | 0 | 0.679688 |
| task1_radar | L5 | 128x1024 | true | 3.873190 | 33.715600 | 8.705 | 0.0544498 | 0.00109335 | 0 | 0.96875 |
| task2_features | L5 | 80x2048 | true | 245.033000 | 4126.410000 | 16.840 | 0.00206816 | 0.000596115 | 0 | 1.17969 |
| task1_radar | L6 | 192x1536 | true | 8.827360 | 71.750500 | 8.128 | 0.335136 | 0.0254083 | 0 | 2.73047 |
| task2_features | L6 | 96x3072 | true | 416.534000 | 8795.660000 | 21.116 | 0.000853242 | 0.0347257 | 0 | 3.02734 |

## Artifacts

- scale csv: `data/reports/demo/latest_task_demo_scale_benchmark.csv`
- scale json: `data/reports/demo/latest_task_demo_scale_report.json`
- scale markdown: `data/reports/demo/latest_task_demo_scale_report.md`
