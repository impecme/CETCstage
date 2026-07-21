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
| input_construction | 14250.803711 | 4.077844 | 4.051850 |
| filter | 43.344975 | 2.458909 | 2.435598 |
| demod | 14.733784 | 0.295831 | 0.259214 |
| correlate | 9341.382812 | 2.218678 | 2.150980 |
| spectrogram | 61.401848 | 3.773453 | 3.700870 |
| cwt | 4575.521973 | 12.512743 | 12.451737 |
| feature_fusion | 2.187827 | 0.727583 | 0.702460 |
| measurement_conversion | 0.000290 | 0.000000 | 0.000000 |
| kalman | 0.188151 | 0.102290 | 0.078494 |
| total | 28289.564453 | 26.167330 | 25.831202 |

## Validation

- pass: `true`
- repeat_runs: `7`
- gpu_free_delta_mib: `-112.000`
- rss_current_delta_mib: `401.902`

## Artifacts

- inputs: `data/generated/demo/task2_features/input/`
- samples: `data/generated/demo/task2_features/output_samples/`
- metrics: `data/.reports_staging/demo/task2_features/latest_metrics.json`
- timings: `data/.reports_staging/demo/task2_features/latest_stage_timings.csv`
