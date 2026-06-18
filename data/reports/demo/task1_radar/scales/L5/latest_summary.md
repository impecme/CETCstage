# Task 1 Radar Demo

## Scenario

- scale_level: `L5`
- scale_value: `131072`
- fs: `1e+06`
- num_pulses: `128`
- samples_per_pulse: `1024`
- template_length: `256`
- prf: `2000`
- delay_samples: `192`
- doppler_hz: `125`
- snr_db: `20`

## Detection

| backend | found | range_bin | doppler_bin | doppler_hz | power |
| --- | --- | ---: | ---: | ---: | ---: |
| expected | true | 192 | 72 | 125.000 | 1032256.000 |
| cpu | true | 192 | 72 | 125.000 | 1031906.312 |
| gpu | true | 192 | 72 | 125.000 | 1031906.312 |

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| pulse_compression | 1.120492e-05 | 4.264961e-06 | 5.141383e-04 | 3.905723e-07 |
| pulse_doppler | 6.803076e-05 | 1.930101e-04 | 1.617840e-03 | 2.956324e-06 |
| cfar_threshold | 5.444980e-02 | 5.444980e-02 | 2.115353e-02 | 5.239162e-03 |
| ambgfun_surface | 7.630769e-06 | 1.788139e-07 | 4.708489e+01 | 7.262921e-09 |

## Timing

| stage | cpu_ms | gpu_ms |
| --- | ---: | ---: |
| pulse_compression | 5.563723 | 1.662647 |
| pulse_doppler | 19.071871 | 0.925573 |
| power_map | 0.044840 | 0.126211 |
| ca_cfar | 0.420482 | 0.481942 |
| ambgfun | 9.078148 | 0.630723 |
| total | 34.179062 | 3.827096 |

## Validation

- pass: `true`
- repeat_runs: `3`
- cuda_free_delta_mib: `-128.000`
- rss_current_delta_mib: `384.340`

## Artifacts

- inputs: `data/generated/demo/task1_radar/input/`
- samples: `data/generated/demo/task1_radar/output_samples/`
- metrics: `data/reports/demo/task1_radar/latest_metrics.json`
- timings: `data/reports/demo/task1_radar/latest_stage_timings.csv`
- figures: run `python3 demo/task1_radar/visualize_task1.py`
