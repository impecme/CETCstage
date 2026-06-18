# Task Demo Validation Report

- pass: `true`
- repeat: `3`
- compute_sanitizer: `not_requested`
- asan_lsan: `not_requested`
- visualization: `available`

| task | scale | validation | gpu_ms | cpu_ms | speedup | max_mixed_error | failed_checks |
| --- | ---: | --- | ---: | ---: | ---: | ---: | --- |
| task1_radar | L3 | true | 2.240990 | 5.310230 | 2.370 | 0.00248718 | - |
| task2_features | L3 | true | 122.416000 | 879.742000 | 7.186 | 0.0031292 | - |

## Artifacts

- task1_radar metrics: `data/reports/demo/task1_radar/latest_metrics.json`
- task1_radar summary: `data/reports/demo/task1_radar/latest_summary.md`
- task2_features metrics: `data/reports/demo/task2_features/latest_metrics.json`
- task2_features summary: `data/reports/demo/task2_features/latest_summary.md`
- aggregate json: `data/reports/demo/latest_task_demo_report.json`
- aggregate markdown: `data/reports/demo/latest_task_demo_report.md`
