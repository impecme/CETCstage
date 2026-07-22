# Task 2 Feature Localization Demo

## Scenario

- scale_level: `L5`
- scale_value: `294912`
- fs: `1e+06`
- num_frames: `96`
- samples_per_frame: `3072`
- template_length: `1024`
- target_start_sample_0: `660`
- target_step_per_frame: `3`
- interferer_start_sample: `1920`
- snr_db: `12`

## Consistency

- cpu_gpu_track_match: `true`
- gpu_matches_truth_within_tolerance: `true`
- gpu_kalman_rmse: `0.4004` samples

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| filtered | 4.077728e-06 | 1.195441e-06 | 5.819851e-05 | 8.910531e-08 |
| correlate | 9.295321e-06 | 5.960464e-07 | 9.639815e-01 | 3.802521e-08 |
| spectrogram | 9.139476e-07 | 2.980232e-08 | 1.209703e+00 | 3.779499e-09 |
| cwt | 1.804577e-06 | 6.027147e-07 | 6.506193e+00 | 7.495594e-08 |
| feature_score | 9.837028e-05 | 1.855195e-06 | 3.863798e-02 | 4.322485e-08 |
| kalman_track | 8.848596e-04 | 1.259155e+00 | 8.848596e-04 | 4.003836e-01 |

## Timing

| stage | cpu_ms | gpu_ms | gpu_kernel_ms |
| --- | ---: | ---: | ---: |
| input_construction | 10718.325195 | 4.134110 | 4.108180 |
| filter | 33.463020 | 1.943913 | 1.925186 |
| demod | 11.040078 | 0.247855 | 0.216720 |
| correlate | 7147.425293 | 1.760058 | 1.697752 |
| spectrogram | 46.032795 | 2.965945 | 2.899458 |
| cwt | 3391.845703 | 9.591572 | 9.519027 |
| feature_fusion | 1.643265 | 0.620103 | 0.571956 |
| measurement_conversion | 0.000480 | 0.000000 | 0.000000 |
| kalman | 0.128313 | 0.117253 | 0.075606 |
| total | 21349.904297 | 21.380810 | 21.013885 |

## Validation

- pass: `true`
- repeat_runs: `7`
- gpu_free_delta_mib: `-88.000`
- rss_current_delta_mib: `390.828`

## Artifacts

- inputs: `data/generated/demo/task2_features/input/`
- samples: `data/generated/demo/task2_features/output_samples/`
- metrics: `data/.reports_staging/demo/task2_features/latest_metrics.json`
- timings: `data/.reports_staging/demo/task2_features/latest_stage_timings.csv`
