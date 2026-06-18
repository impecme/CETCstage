# Task 2 Feature Localization Demo

## Scenario

- scale_level: `L5`
- scale_value: `163840`
- fs: `1e+06`
- num_frames: `80`
- samples_per_frame: `2048`
- template_length: `512`
- target_start_sample_0: `440`
- target_step_per_frame: `3`
- interferer_start_sample: `1280`
- snr_db: `12`

## Consistency

- cpu_gpu_track_match: `true`
- gpu_matches_truth_within_tolerance: `true`
- gpu_kalman_rmse: `0.5174` samples

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| filtered | 7.166876e-06 | 9.547215e-07 | 1.051566e-04 | 7.391629e-08 |
| correlate | 4.353402e-06 | 1.072884e-06 | 1.121020e-04 | 3.780763e-08 |
| spectrogram | 9.485750e-07 | 2.235174e-08 | 1.199088e+00 | 3.868212e-09 |
| cwt | 1.311593e-06 | 3.998401e-07 | 5.934205e-01 | 6.043030e-08 |
| feature_score | 9.231322e-05 | 2.946239e-06 | 1.311400e-02 | 1.138887e-07 |
| kalman_track | 2.068159e-03 | 1.650391e+00 | 2.068159e-03 | 5.174360e-01 |

## Timing

| stage | cpu_ms | gpu_ms |
| --- | ---: | ---: |
| filter | 14.315751 | 2.685321 |
| demod | 5.602907 | 0.167780 |
| correlate | 2108.280762 | 127.497116 |
| spectrogram | 38.722954 | 65.629654 |
| cwt | 1871.668945 | 54.511520 |
| feature_fusion | 0.917942 | 0.376092 |
| kalman | 0.107201 | 0.126020 |
| total | 4039.616455 | 250.993515 |

## Validation

- pass: `true`
- repeat_runs: `3`
- cuda_free_delta_mib: `-48.000`
- rss_current_delta_mib: `375.023`

## Artifacts

- inputs: `data/generated/demo/task2_features/input/`
- samples: `data/generated/demo/task2_features/output_samples/`
- metrics: `data/reports/demo/task2_features/latest_metrics.json`
- timings: `data/reports/demo/task2_features/latest_stage_timings.csv`
- figures: run `python3 demo/task2_features/visualize_task2.py`
