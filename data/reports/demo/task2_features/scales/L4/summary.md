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
| input_construction | 7246.738770 | 2.169111 | 2.147956 |
| filter | 22.246008 | 1.509558 | 1.486584 |
| demod | 7.354696 | 0.208784 | 0.174744 |
| correlate | 4755.053711 | 1.333795 | 1.271334 |
| spectrogram | 30.599386 | 2.101658 | 2.040556 |
| cwt | 2259.944336 | 6.340991 | 6.274514 |
| feature_fusion | 1.102809 | 0.402648 | 0.375460 |
| measurement_conversion | 0.000120 | 0.000000 | 0.000000 |
| kalman | 0.113032 | 0.096512 | 0.064022 |
| total | 14323.152344 | 14.163057 | 13.835169 |

## Validation

- pass: `true`
- repeat_runs: `7`
- gpu_free_delta_mib: `-80.000`
- rss_current_delta_mib: `381.578`

## Artifacts

- inputs: `data/generated/demo/task2_features/input/`
- samples: `data/generated/demo/task2_features/output_samples/`
- metrics: `data/.reports_staging/demo/task2_features/latest_metrics.json`
- timings: `data/.reports_staging/demo/task2_features/latest_stage_timings.csv`
