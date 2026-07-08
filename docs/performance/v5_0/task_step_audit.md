# V5.3 Task1/Task2 步骤审计

本文件由 `scripts/test/audit_task_steps.py` 根据机器可读步骤契约生成。
`public` 表示完全调用公共算子；`mixed` 表示公共算子加任务辅助函数，按当前验收口径也属于公共算子实现链路。

- status: `passed`
- steps/calculation: `16` / `14`
- public calculation: `6`
- calculation steps with public-operator link: `14`
- mixed/private helper steps: `8`
- timing/accuracy gaps: `0` / `0`

| 任务 | 步骤 | 公共算子 | 实现 | 计时 | 精度 | 迁移目标 |
| --- | --- | --- | --- | --- | --- | --- |
| task1_radar | signal_generation | waveforms/chirp | orchestration | missing | business_only | demo input construction is allowed |
| task1_radar | pulse_compression | radartools/pulse_compression | public | present | present | none |
| task1_radar | pulse_doppler_fftshift | radartools/pulse_doppler, radartools/fftshift_rows | public | present | present | none |
| task1_radar | power_map | radartools/power_map | public | present | present | none |
| task1_radar | ca_cfar | radartools/ca_cfar | public | present | present | none |
| task1_radar | ambgfun | radartools/ambgfun | public | present | present | none |
| task1_radar | final_detection | radartools/detect_peak | public | present | present | none |
| task2_features | signal_generation | waveforms/chirp, waveforms/gausspulse, waveforms/sawtooth, waveforms/square | orchestration | missing | business_only | demo input construction is allowed |
| task2_features | filter | filter_design/firwin, filtering/firfilter | mixed | present | present | helper is acceptable because public firfilter performs the core filtering; only revisit if Task2 filter timing requires a fused public API |
| task2_features | demod | demod/fm_demod | mixed | present | present | helper is acceptable because public fm_demod defines the core demodulation semantics; batched score keeps Task2 timing compact |
| task2_features | correlate | correlate/correlate | mixed | present | present | move magnitude and normalization post-processing to public operators |
| task2_features | spectrogram | spectral/spectrogram | mixed | present | present | move band scoring and sample-axis projection to a public spectral helper |
| task2_features | cwt | wavelets/cwt | mixed | present | present | move scale reduction and normalization to a public wavelets helper |
| task2_features | feature_fusion_peak | bsplines/cubic, peak_finding/argrelmax | mixed | present | present | add public weighted fusion, smoothing, and candidate peak-selection operators |
| task2_features | measurement_conversion | estimation/kalman_filter | mixed | present | present | helper is acceptable because it prepares the public Kalman measurement vector and is now timed/validated independently |
| task2_features | kalman | estimation/kalman_filter | mixed | present | present | helper is acceptable because it implements the same Kalman state equations as the public CPU operator and reports CPU/GPU track error |
