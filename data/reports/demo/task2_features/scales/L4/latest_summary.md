# Task 2 Feature Localization Demo

## Scenario

- scale_level: `L4`
- scale_value: `98304`
- fs: `1e+06`
- num_frames: `64`
- samples_per_frame: `1536`
- template_length: `384`
- target_start_sample_0: `330`
- target_step_per_frame: `3`
- interferer_start_sample: `960`
- snr_db: `12`

## Consistency

- cpu_gpu_track_match: `true`
- gpu_matches_truth_within_tolerance: `true`
- gpu_kalman_rmse: `0.6413` samples

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| filtered | 5.420518e-06 | 1.311641e-06 | 2.784427e-04 | 7.535176e-08 |
| correlate | 4.529739e-06 | 7.748604e-07 | 5.353101e-05 | 4.011477e-08 |
| spectrogram | 1.044723e-06 | 2.980232e-08 | 8.611280e-01 | 5.150028e-09 |
| cwt | 1.467556e-06 | 9.310543e-07 | 7.769230e-01 | 6.701553e-08 |
| feature_score | 8.052475e-05 | 2.808869e-06 | 1.263842e-01 | 9.861891e-08 |
| kalman_track | 3.087919e-03 | 1.886719e+00 | 3.087919e-03 | 6.412948e-01 |

## Timing

| stage | cpu_ms | gpu_ms |
| --- | ---: | ---: |
| filter | 7.625722 | 1.796727 |
| demod | 3.445719 | 0.148601 |
| correlate | 982.619812 | 87.935921 |
| spectrogram | 21.977968 | 34.403252 |
| cwt | 1351.769531 | 38.281754 |
| feature_fusion | 0.551974 | 0.242201 |
| kalman | 0.095650 | 0.123110 |
| total | 2368.086426 | 162.931564 |

## Validation

- pass: `true`
- repeat_runs: `3`
- cuda_free_delta_mib: `-48.000`
- rss_current_delta_mib: `369.160`

## Artifacts

- inputs: `data/generated/demo/task2_features/input/`
- samples: `data/generated/demo/task2_features/output_samples/`
- metrics: `data/reports/demo/task2_features/latest_metrics.json`
- timings: `data/reports/demo/task2_features/latest_stage_timings.csv`
- figures: run `python3 demo/task2_features/visualize_task2.py`
