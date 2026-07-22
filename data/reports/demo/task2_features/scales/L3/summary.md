# Task 2 Feature Localization Demo

## Scenario

- scale_level: `L3`
- scale_value: `98304`
- fs: `1e+06`
- num_frames: `32`
- samples_per_frame: `3072`
- template_length: `1024`
- target_start_sample_0: `660`
- target_step_per_frame: `3`
- interferer_start_sample: `1920`
- snr_db: `12`

## Consistency

- cpu_gpu_track_match: `true`
- gpu_matches_truth_within_tolerance: `true`
- gpu_kalman_rmse: `0.3039` samples

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| filtered | 3.389839e-06 | 1.195441e-06 | 4.432433e-05 | 8.871683e-08 |
| correlate | 6.514433e-06 | 9.536743e-07 | 5.212022e-05 | 4.699488e-08 |
| spectrogram | 8.998099e-07 | 2.980232e-08 | 1.563105e+00 | 3.715461e-09 |
| cwt | 1.785237e-06 | 4.009492e-07 | 7.352849e+00 | 7.371465e-08 |
| feature_score | 6.179699e-05 | 1.147389e-06 | 5.814969e-03 | 5.942553e-08 |
| kalman_track | 4.177807e-04 | 5.468750e-01 | 4.177807e-04 | 3.038583e-01 |

## Timing

| stage | cpu_ms | gpu_ms | gpu_kernel_ms |
| --- | ---: | ---: | ---: |
| input_construction | 3562.093994 | 1.511544 | 1.466076 |
| filter | 10.735769 | 0.913525 | 0.875660 |
| demod | 3.682418 | 0.196313 | 0.149524 |
| correlate | 2357.647461 | 2.136124 | 2.071798 |
| spectrogram | 15.219418 | 1.985402 | 1.925790 |
| cwt | 1129.229248 | 3.348573 | 3.282128 |
| feature_fusion | 0.546045 | 0.240974 | 0.217548 |
| measurement_conversion | 0.000340 | 0.000000 | 0.000000 |
| kalman | 0.071781 | 0.081621 | 0.059912 |
| total | 7079.226562 | 10.414076 | 10.048436 |

## Validation

- pass: `true`
- repeat_runs: `7`
- gpu_free_delta_mib: `-48.000`
- rss_current_delta_mib: `371.410`

## Artifacts

- inputs: `data/generated/demo/task2_features/input/`
- samples: `data/generated/demo/task2_features/output_samples/`
- metrics: `data/.reports_staging/demo/task2_features/latest_metrics.json`
- timings: `data/.reports_staging/demo/task2_features/latest_stage_timings.csv`
