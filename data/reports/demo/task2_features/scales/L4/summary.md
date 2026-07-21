# Task 2 Feature Localization Demo

## Scenario

- scale_level: `L4`
- scale_value: `196608`
- fs: `1e+06`
- num_frames: `64`
- samples_per_frame: `3072`
- template_length: `1024`
- target_start_sample_0: `660`
- target_step_per_frame: `3`
- interferer_start_sample: `1920`
- snr_db: `12`

## Consistency

- cpu_gpu_track_match: `true`
- gpu_matches_truth_within_tolerance: `true`
- gpu_kalman_rmse: `0.3301` samples

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| filtered | 3.356818e-06 | 1.195441e-06 | 5.819851e-05 | 8.888910e-08 |
| correlate | 7.835489e-06 | 5.960464e-07 | 9.639815e-01 | 3.772541e-08 |
| spectrogram | 1.068430e-06 | 2.980232e-08 | 7.657388e+00 | 3.814047e-09 |
| cwt | 1.290361e-06 | 5.967910e-07 | 2.565990e+00 | 7.472111e-08 |
| feature_score | 9.837028e-05 | 1.855195e-06 | 3.432568e-02 | 4.364650e-08 |
| kalman_track | 8.848596e-04 | 1.259155e+00 | 8.848596e-04 | 3.300502e-01 |

## Timing

| stage | cpu_ms | gpu_ms | gpu_kernel_ms |
| --- | ---: | ---: | ---: |
| input_construction | 7138.358887 | 2.023044 | 1.996658 |
| filter | 22.354591 | 1.497104 | 1.477268 |
| demod | 7.321928 | 0.203421 | 0.170366 |
| correlate | 4741.630859 | 1.352463 | 1.281266 |
| spectrogram | 30.409624 | 2.129576 | 2.066904 |
| cwt | 2286.172607 | 6.294625 | 6.219844 |
| feature_fusion | 1.091853 | 0.400981 | 0.374468 |
| measurement_conversion | 0.000120 | 0.000000 | 0.000000 |
| kalman | 0.107320 | 0.096761 | 0.063938 |
| total | 14227.447266 | 13.997974 | 13.650712 |

## Validation

- pass: `true`
- repeat_runs: `7`
- gpu_free_delta_mib: `-80.000`
- rss_current_delta_mib: `381.395`

## Artifacts

- inputs: `data/generated/demo/task2_features/input/`
- samples: `data/generated/demo/task2_features/output_samples/`
- metrics: `data/.reports_staging/demo/task2_features/latest_metrics.json`
- timings: `data/.reports_staging/demo/task2_features/latest_stage_timings.csv`
