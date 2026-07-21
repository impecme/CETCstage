# Task 2 Feature Localization Demo

## Scenario

- scale_level: `L2`
- scale_value: `49152`
- fs: `1e+06`
- num_frames: `16`
- samples_per_frame: `3072`
- template_length: `1024`
- target_start_sample_0: `660`
- target_step_per_frame: `3`
- interferer_start_sample: `1920`
- snr_db: `12`

## Consistency

- cpu_gpu_track_match: `true`
- gpu_matches_truth_within_tolerance: `true`
- gpu_kalman_rmse: `0.3354` samples

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| filtered | 2.530201e-06 | 1.195441e-06 | 4.432433e-05 | 8.937170e-08 |
| correlate | 6.514433e-06 | 8.344650e-07 | 5.212022e-05 | 4.909085e-08 |
| spectrogram | 8.511638e-07 | 3.725290e-08 | 1.023786e+00 | 3.621978e-09 |
| cwt | 1.418128e-06 | 5.990192e-07 | 9.075560e-01 | 7.321960e-08 |
| feature_score | 2.367967e-05 | 4.842877e-07 | 1.249833e-03 | 5.669679e-08 |
| kalman_track | 4.177807e-04 | 5.468750e-01 | 4.177807e-04 | 3.354056e-01 |

## Timing

| stage | cpu_ms | gpu_ms | gpu_kernel_ms |
| --- | ---: | ---: | ---: |
| input_construction | 1777.772461 | 1.092952 | 1.061148 |
| filter | 5.489067 | 0.640921 | 0.605226 |
| demod | 1.837425 | 0.163090 | 0.122730 |
| correlate | 1158.196777 | 1.284712 | 1.218198 |
| spectrogram | 7.689928 | 1.241942 | 1.182466 |
| cwt | 570.925537 | 1.792502 | 1.735412 |
| feature_fusion | 0.273530 | 0.218040 | 0.182152 |
| measurement_conversion | 0.000080 | 0.000000 | 0.000000 |
| kalman | 0.047940 | 0.096790 | 0.059310 |
| total | 3522.232422 | 6.530949 | 6.166642 |

## Validation

- pass: `true`
- repeat_runs: `7`
- gpu_free_delta_mib: `-48.000`
- rss_current_delta_mib: `366.109`

## Artifacts

- inputs: `data/generated/demo/task2_features/input/`
- samples: `data/generated/demo/task2_features/output_samples/`
- metrics: `data/.reports_staging/demo/task2_features/latest_metrics.json`
- timings: `data/.reports_staging/demo/task2_features/latest_stage_timings.csv`
