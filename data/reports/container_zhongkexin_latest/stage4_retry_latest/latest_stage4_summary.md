# Zhongkexin V4.4 Stage4 Pilot Summary

- pass: `True`
- version: `diagnostics-20260617-stage4-perf-full-v4`
- task_scales: `3`
- task_log: `data/reports/zhongkexin/stage4/latest_task_scale_pilot.log`
- benchmark_modules: `windows,filter_design,filtering,radartools,spectral,correlate,peak_finding`
- benchmark_operators: `chebwin,kaiser_beta,kaiser_atten,cmplx_sort,firwin2,lfilter,firfilter_zi,filtfilt,mvdr,periodogram,welch,coherence,correlation_lags,argrelmin,argrelmax`
- benchmark_scale_levels: `1,2,3,4,5,6`
- benchmark_log: `data/reports/zhongkexin/stage4/latest_operator_benchmark_pilot.log`
- benchmark_csv: `data/reports/unit/benchmarks/zhongkexin_stage4_retry/latest_all_ops_scale_benchmark.csv`
- benchmark_rows: `90`
- benchmark_failed_rows: `0`
- plot_status: `passed`
- figure_dir: `data/reports/unit/benchmarks/zhongkexin_stage4_retry/figures`
