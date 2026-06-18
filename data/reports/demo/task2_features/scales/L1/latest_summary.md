# Task 2 Feature Localization Demo

## Scenario

- scale_level: `L1`
- scale_value: `8192`
- fs: `1e+06`
- num_frames: `16`
- samples_per_frame: `512`
- template_length: `128`
- target_start_sample_0: `110`
- target_step_per_frame: `3`
- interferer_start_sample: `320`
- snr_db: `12`

## Consistency

- cpu_gpu_track_match: `true`
- gpu_matches_truth_within_tolerance: `true`
- gpu_kalman_rmse: `0.4536` samples

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| filtered | 5.954345e-06 | 7.158764e-07 | 1.726692e-05 | 5.933884e-08 |
| correlate | 2.953645e-06 | 6.556511e-07 | 2.661535e-05 | 5.250769e-08 |
| spectrogram | 8.068781e-07 | 4.114645e-08 | 2.840534e-02 | 6.213262e-09 |
| cwt | 7.684480e-07 | 2.980232e-07 | 2.982652e-04 | 4.993035e-08 |
| feature_score | 3.055418e-05 | 5.438924e-07 | 1.795843e-03 | 7.536494e-08 |
| kalman_track | 3.935632e-03 | 8.461609e-01 | 3.935632e-03 | 4.536333e-01 |

## Timing

| stage | cpu_ms | gpu_ms |
| --- | ---: | ---: |
| filter | 0.319191 | 0.574062 |
| demod | 0.299924 | 0.121411 |
| correlate | 25.180887 | 14.029449 |
| spectrogram | 8.232972 | 7.454547 |
| cwt | 87.901100 | 7.733358 |
| feature_fusion | 0.048790 | 0.090971 |
| kalman | 0.037790 | 0.120350 |
| total | 122.020653 | 30.124147 |

## Validation

- pass: `true`
- repeat_runs: `3`
- cuda_free_delta_mib: `-48.000`
- rss_current_delta_mib: `360.688`

## Artifacts

- inputs: `data/generated/demo/task2_features/input/`
- samples: `data/generated/demo/task2_features/output_samples/`
- metrics: `data/reports/demo/task2_features/latest_metrics.json`
- timings: `data/reports/demo/task2_features/latest_stage_timings.csv`
- figures: run `python3 demo/task2_features/visualize_task2.py`
