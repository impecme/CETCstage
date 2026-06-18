# Task 2 Feature Localization Demo

## Scenario

- scale_level: `L3`
- scale_value: `49152`
- fs: `1e+06`
- num_frames: `48`
- samples_per_frame: `1024`
- template_length: `256`
- target_start_sample_0: `220`
- target_step_per_frame: `3`
- interferer_start_sample: `640`
- snr_db: `12`

## Consistency

- cpu_gpu_track_match: `true`
- gpu_matches_truth_within_tolerance: `true`
- gpu_kalman_rmse: `0.5070` samples

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| filtered | 5.814821e-06 | 8.471412e-07 | 7.469460e-05 | 6.897260e-08 |
| correlate | 4.503968e-06 | 8.940697e-07 | 3.247903e-05 | 4.485614e-08 |
| spectrogram | 1.230817e-06 | 3.069283e-08 | 6.868935e-01 | 5.675681e-09 |
| cwt | 1.326531e-06 | 4.915125e-07 | 2.176065e-01 | 5.448284e-08 |
| feature_score | 3.214336e-05 | 9.983778e-07 | 2.117556e-02 | 8.240944e-08 |
| kalman_track | 3.129203e-03 | 1.326782e+00 | 3.129203e-03 | 5.070406e-01 |

## Timing

| stage | cpu_ms | gpu_ms |
| --- | ---: | ---: |
| filter | 2.969133 | 0.945374 |
| demod | 1.719707 | 0.125361 |
| correlate | 321.108337 | 52.221504 |
| spectrogram | 16.064440 | 23.457960 |
| cwt | 550.016418 | 24.812750 |
| feature_fusion | 0.280361 | 0.160780 |
| kalman | 0.062761 | 0.115811 |
| total | 892.221130 | 101.839546 |

## Validation

- pass: `true`
- repeat_runs: `3`
- cuda_free_delta_mib: `-48.000`
- rss_current_delta_mib: `364.645`

## Artifacts

- inputs: `data/generated/demo/task2_features/input/`
- samples: `data/generated/demo/task2_features/output_samples/`
- metrics: `data/reports/demo/task2_features/latest_metrics.json`
- timings: `data/reports/demo/task2_features/latest_stage_timings.csv`
- figures: run `python3 demo/task2_features/visualize_task2.py`
