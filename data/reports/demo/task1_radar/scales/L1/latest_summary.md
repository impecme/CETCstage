# Task 1 Radar Demo

## Scenario

- scale_level: `L1`
- scale_value: `4096`
- fs: `1e+06`
- num_pulses: `32`
- samples_per_pulse: `128`
- template_length: `32`
- prf: `2000`
- delay_samples: `24`
- doppler_hz: `125`
- snr_db: `20`

## Detection

| backend | found | range_bin | doppler_bin | doppler_hz | power |
| --- | --- | ---: | ---: | ---: | ---: |
| expected | true | 24 | 18 | 125.000 | 7687.999 |
| cpu | true | 24 | 18 | 125.000 | 7723.354 |
| gpu | true | 24 | 18 | 125.000 | 7723.352 |

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| pulse_compression | 9.395972e-06 | 1.107924e-06 | 9.227314e-05 | 2.661681e-07 |
| pulse_doppler | 7.878280e-06 | 1.625492e-05 | 1.011162e-04 | 1.044521e-06 |
| cfar_threshold | 2.785325e-04 | 3.929138e-04 | 4.294109e-04 | 7.059854e-05 |
| ambgfun_surface | 8.323069e-06 | 1.192093e-07 | 4.814620e+00 | 1.631135e-08 |

## Timing

| stage | cpu_ms | gpu_ms |
| --- | ---: | ---: |
| pulse_compression | 1.038484 | 0.734733 |
| pulse_doppler | 0.368361 | 0.564762 |
| power_map | 0.001360 | 0.105511 |
| ca_cfar | 0.007470 | 0.270611 |
| ambgfun | 0.466352 | 0.453671 |
| total | 1.882027 | 2.129288 |

## Validation

- pass: `true`
- repeat_runs: `3`
- cuda_free_delta_mib: `-112.000`
- rss_current_delta_mib: `360.633`

## Artifacts

- inputs: `data/generated/demo/task1_radar/input/`
- samples: `data/generated/demo/task1_radar/output_samples/`
- metrics: `data/reports/demo/task1_radar/latest_metrics.json`
- timings: `data/reports/demo/task1_radar/latest_stage_timings.csv`
- figures: run `python3 demo/task1_radar/visualize_task1.py`
