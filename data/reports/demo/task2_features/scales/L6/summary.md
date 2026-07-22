# Task 2 Feature Localization Demo

## Scenario

- scale_level: `L6`
- scale_value: `393216`
- fs: `1e+06`
- num_frames: `128`
- samples_per_frame: `3072`
- template_length: `1024`
- target_start_sample_0: `660`
- target_step_per_frame: `3`
- interferer_start_sample: `1920`
- snr_db: `12`

## Consistency

- cpu_gpu_track_match: `true`
- gpu_matches_truth_within_tolerance: `true`
- gpu_kalman_rmse: `0.4779` samples

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| filtered | 4.093899e-06 | 1.669994e-06 | 1.932453e-04 | 8.915796e-08 |
| correlate | 9.295321e-06 | 6.556511e-07 | 9.639815e-01 | 3.846130e-08 |
| spectrogram | 1.051609e-06 | 2.980232e-08 | 6.167496e+00 | 3.905336e-09 |
| cwt | 1.812844e-06 | 5.960464e-07 | 7.808838e-01 | 7.857953e-08 |
| feature_score | 9.837028e-05 | 3.010035e-06 | 3.863798e-02 | 4.384898e-08 |
| kalman_track | 8.848596e-04 | 1.321045e+00 | 8.848596e-04 | 4.778552e-01 |

## Timing

| stage | cpu_ms | gpu_ms | gpu_kernel_ms |
| --- | ---: | ---: | ---: |
| input_construction | 14173.964844 | 4.008308 | 3.984680 |
| filter | 43.423222 | 2.375558 | 2.354872 |
| demod | 14.743473 | 0.302357 | 0.264430 |
| correlate | 9490.303711 | 2.190555 | 2.127200 |
| spectrogram | 61.403831 | 3.763362 | 3.695984 |
| cwt | 4533.266602 | 12.586143 | 12.514034 |
| feature_fusion | 2.220531 | 0.737489 | 0.702844 |
| measurement_conversion | 0.001080 | 0.000000 | 0.000000 |
| kalman | 0.185305 | 0.147953 | 0.078606 |
| total | 28319.513672 | 26.111725 | 25.722651 |

## Validation

- pass: `true`
- repeat_runs: `7`
- gpu_free_delta_mib: `-112.000`
- rss_current_delta_mib: `401.914`

## Artifacts

- inputs: `data/generated/demo/task2_features/input/`
- samples: `data/generated/demo/task2_features/output_samples/`
- metrics: `data/.reports_staging/demo/task2_features/latest_metrics.json`
- timings: `data/.reports_staging/demo/task2_features/latest_stage_timings.csv`
