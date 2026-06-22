# V5.3 Task1/Task2 步骤审计

本文件由 `scripts/test/audit_task_steps.py` 根据机器可读步骤契约生成。
`public` 表示已完全调用公共算子；`mixed/private` 是 V5.3-03/04 的迁移清单。

- status: `passed`
- steps/calculation: `16` / `14`
- public calculation: `6`
- migration steps: `8`
- timing/accuracy gaps: `1` / `4`

| 任务 | 步骤 | 公共算子 | 实现 | 计时 | 精度 | 迁移目标 |
| --- | --- | --- | --- | --- | --- | --- |
| task1_radar | signal_generation | waveforms/chirp | orchestration | missing | business_only | demo input construction is allowed |
| task1_radar | pulse_compression | radartools/pulse_compression | public | present | present | none |
| task1_radar | pulse_doppler_fftshift | radartools/pulse_doppler, radartools/fftshift_rows | public | present | present | none |
| task1_radar | power_map | radartools/power_map | public | present | present | none |
| task1_radar | ca_cfar | radartools/ca_cfar | public | present | present | none |
| task1_radar | ambgfun | radartools/ambgfun | public | present | present | none |
| task1_radar | final_detection | radartools/detect_peak | public | present | business_only | none |
| task2_features | signal_generation | waveforms/chirp, waveforms/gausspulse, waveforms/sawtooth, waveforms/square | orchestration | missing | business_only | demo input construction is allowed |
| task2_features | filter | filter_design/firwin, filtering/firfilter | mixed | present | present | add a public complex64 filtering path and remove task-local split/combine |
| task2_features | demod | demod/fm_demod | mixed | present | missing | use the public GPU fm_demod operator and public score post-processing |
| task2_features | correlate | correlate/correlate | mixed | present | present | move magnitude and normalization post-processing to public operators |
| task2_features | spectrogram | spectral/spectrogram | mixed | present | present | move band scoring and sample-axis projection to a public spectral helper |
| task2_features | cwt | wavelets/cwt | mixed | present | present | move scale reduction and normalization to a public wavelets helper |
| task2_features | feature_fusion_peak | bsplines/cubic, peak_finding/argrelmax | mixed | present | present | add public weighted fusion, smoothing, and candidate peak-selection operators |
| task2_features | measurement_conversion | - | private | bundled | bundled | move index-to-measurement conversion to a public estimation helper |
| task2_features | kalman | estimation/kalman_filter | mixed | present | business_only | use the public GPU KalmanFilter interface and add CPU/GPU step error |
