# Task 2 Feature Localization Demo

## Scenario

- scale_level: `L1`
- scale_value: `24576`
- fs: `1e+06`
- num_frames: `8`
- samples_per_frame: `3072`
- template_length: `1024`
- target_start_sample_0: `660`
- target_step_per_frame: `3`
- interferer_start_sample: `1920`
- snr_db: `12`

## Consistency

- cpu_gpu_track_match: `true`
- gpu_matches_truth_within_tolerance: `true`
- gpu_kalman_rmse: `0.3492` samples

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| filtered | 2.530201e-06 | 1.195441e-06 | 2.461528e-05 | 9.007056e-08 |
| correlate | 6.514433e-06 | 7.748604e-07 | 5.212022e-05 | 5.120096e-08 |
| spectrogram | 9.280711e-07 | 2.980232e-08 | 1.129944e+00 | 3.852802e-09 |
| cwt | 1.457567e-06 | 1.073814e-06 | 1.457828e+00 | 7.349153e-08 |
| feature_score | 2.276237e-05 | 4.842877e-07 | 1.249833e-03 | 6.487338e-08 |
| kalman_track | 4.177807e-04 | 5.468750e-01 | 4.177807e-04 | 3.491564e-01 |

## Timing

| stage | cpu_ms | gpu_ms | gpu_kernel_ms |
| --- | ---: | ---: | ---: |
| input_construction | 908.963562 | 1.340966 | 1.309266 |
| filter | 2.795603 | 0.636877 | 0.604438 |
| demod | 0.922801 | 0.186312 | 0.148620 |
| correlate | 606.964417 | 0.780849 | 0.709024 |
| spectrogram | 3.875613 | 0.914881 | 0.819094 |
| cwt | 282.580963 | 1.093353 | 1.016414 |
| feature_fusion | 0.137412 | 0.214593 | 0.176024 |
| measurement_conversion | 0.000080 | 0.000000 | 0.000000 |
| kalman | 0.043741 | 0.103281 | 0.070080 |
| total | 1806.284180 | 5.271112 | 4.852960 |

## Validation

- pass: `true`
- repeat_runs: `7`
- gpu_free_delta_mib: `-48.000`
- rss_current_delta_mib: `363.090`

## Artifacts

- inputs: `data/generated/demo/task2_features/input/`
- samples: `data/generated/demo/task2_features/output_samples/`
- metrics: `data/.reports_staging/demo/task2_features/latest_metrics.json`
- timings: `data/.reports_staging/demo/task2_features/latest_stage_timings.csv`
