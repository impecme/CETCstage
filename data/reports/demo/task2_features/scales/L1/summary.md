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
| input_construction | 914.627441 | 0.763011 | 0.732864 |
| filter | 2.703163 | 0.382240 | 0.351980 |
| demod | 0.910511 | 0.127070 | 0.091962 |
| correlate | 582.743164 | 0.718611 | 0.651520 |
| spectrogram | 3.821077 | 0.757170 | 0.693656 |
| cwt | 309.970947 | 0.985931 | 0.921814 |
| feature_fusion | 0.136080 | 0.176810 | 0.150994 |
| measurement_conversion | 0.000090 | 0.000000 | 0.000000 |
| kalman | 0.037400 | 0.083310 | 0.049190 |
| total | 1814.949951 | 3.994153 | 3.643980 |

## Validation

- pass: `true`
- repeat_runs: `7`
- gpu_free_delta_mib: `-48.000`
- rss_current_delta_mib: `364.555`

## Artifacts

- inputs: `data/generated/demo/task2_features/input/`
- samples: `data/generated/demo/task2_features/output_samples/`
- metrics: `data/.reports_staging/demo/task2_features/latest_metrics.json`
- timings: `data/.reports_staging/demo/task2_features/latest_stage_timings.csv`
