# Task 2 Feature Localization Demo

## Scenario

- scale_level: `L2`
- scale_value: `24576`
- fs: `1e+06`
- num_frames: `32`
- samples_per_frame: `768`
- template_length: `192`
- target_start_sample_0: `165`
- target_step_per_frame: `3`
- interferer_start_sample: `480`
- snr_db: `12`

## Consistency

- cpu_gpu_track_match: `true`
- gpu_matches_truth_within_tolerance: `true`
- gpu_kalman_rmse: `0.6101` samples

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| filtered | 6.909830e-06 | 5.967910e-07 | 3.065050e-05 | 6.573619e-08 |
| correlate | 3.403632e-06 | 7.748604e-07 | 1.322054e-04 | 5.071468e-08 |
| spectrogram | 6.847441e-07 | 4.190952e-08 | 5.743531e-01 | 5.832224e-09 |
| cwt | 1.094138e-06 | 6.027147e-07 | 5.714330e-02 | 5.842256e-08 |
| feature_score | 5.760605e-05 | 8.419156e-07 | 2.120812e-03 | 8.585774e-08 |
| kalman_track | 5.239432e-03 | 1.650421e+00 | 5.239432e-03 | 6.101357e-01 |

## Timing

| stage | cpu_ms | gpu_ms |
| --- | ---: | ---: |
| filter | 1.193545 | 0.656423 |
| demod | 0.862493 | 0.118791 |
| correlate | 123.023697 | 31.322992 |
| spectrogram | 16.217962 | 14.421384 |
| cwt | 271.006744 | 15.573082 |
| feature_fusion | 0.142801 | 0.118251 |
| kalman | 0.043720 | 0.114900 |
| total | 412.490967 | 62.325821 |

## Validation

- pass: `true`
- repeat_runs: `3`
- cuda_free_delta_mib: `-48.000`
- rss_current_delta_mib: `361.484`

## Artifacts

- inputs: `data/generated/demo/task2_features/input/`
- samples: `data/generated/demo/task2_features/output_samples/`
- metrics: `data/reports/demo/task2_features/latest_metrics.json`
- timings: `data/reports/demo/task2_features/latest_stage_timings.csv`
- figures: run `python3 demo/task2_features/visualize_task2.py`
