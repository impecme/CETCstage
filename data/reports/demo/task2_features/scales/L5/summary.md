# Task 2 Feature Localization Demo

## Scenario

- scale_level: `L5`
- scale_value: `294912`
- fs: `1e+06`
- num_frames: `96`
- samples_per_frame: `3072`
- template_length: `1024`
- target_start_sample_0: `660`
- target_step_per_frame: `3`
- interferer_start_sample: `1920`
- snr_db: `12`

## Consistency

- cpu_gpu_track_match: `true`
- gpu_matches_truth_within_tolerance: `true`
- gpu_kalman_rmse: `0.4004` samples

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| filtered | 4.077728e-06 | 1.195441e-06 | 5.819851e-05 | 8.910531e-08 |
| correlate | 9.295321e-06 | 5.960464e-07 | 9.639815e-01 | 3.802521e-08 |
| spectrogram | 9.139476e-07 | 2.980232e-08 | 1.209703e+00 | 3.779499e-09 |
| cwt | 1.804577e-06 | 6.027147e-07 | 6.506193e+00 | 7.495594e-08 |
| feature_score | 9.837028e-05 | 1.855195e-06 | 3.863798e-02 | 4.322485e-08 |
| kalman_track | 8.848596e-04 | 1.259155e+00 | 8.848596e-04 | 4.003836e-01 |

## Timing

| stage | cpu_ms | gpu_ms | gpu_kernel_ms |
| --- | ---: | ---: | ---: |
| input_construction | 10963.956055 | 3.409570 | 3.375528 |
| filter | 32.787277 | 1.982686 | 1.969008 |
| demod | 11.045498 | 0.270521 | 0.231362 |
| correlate | 6966.492676 | 1.787256 | 1.724224 |
| spectrogram | 45.752281 | 2.977709 | 2.910452 |
| cwt | 3721.772949 | 9.547548 | 9.482471 |
| feature_fusion | 1.649423 | 0.580372 | 0.550460 |
| measurement_conversion | 0.000200 | 0.000000 | 0.000000 |
| kalman | 0.146030 | 0.100130 | 0.074678 |
| total | 21743.603516 | 20.655792 | 20.318184 |

## Validation

- pass: `true`
- repeat_runs: `7`
- gpu_free_delta_mib: `-88.000`
- rss_current_delta_mib: `391.504`

## Artifacts

- inputs: `data/generated/demo/task2_features/input/`
- samples: `data/generated/demo/task2_features/output_samples/`
- metrics: `data/.reports_staging/demo/task2_features/latest_metrics.json`
- timings: `data/.reports_staging/demo/task2_features/latest_stage_timings.csv`
