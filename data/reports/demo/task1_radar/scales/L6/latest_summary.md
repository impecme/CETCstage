# Task 1 Radar Demo

## Scenario

- scale_level: `L6`
- scale_value: `294912`
- fs: `1e+06`
- num_pulses: `192`
- samples_per_pulse: `1536`
- template_length: `384`
- prf: `2000`
- delay_samples: `288`
- doppler_hz: `125`
- snr_db: `20`

## Detection

| backend | found | range_bin | doppler_bin | doppler_hz | power |
| --- | --- | ---: | ---: | ---: | ---: |
| expected | true | 288 | 144 | 125.000 | 3502176.000 |
| cpu | true | 288 | 144 | 125.000 | 3501422.250 |
| gpu | true | 288 | 144 | 125.000 | 3501423.250 |

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| pulse_compression | 6.288244e-06 | 6.140404e-06 | 4.536729e+02 | 3.627260e-07 |
| pulse_doppler | 1.226478e-04 | 3.860202e-04 | 5.621671e+02 | 3.471846e-06 |
| cfar_threshold | 3.351364e-01 | 5.000000e-01 | 6.802160e+10 | 1.905936e-02 |
| ambgfun_surface | 1.027944e-05 | 1.788139e-07 | 2.089123e+01 | 6.038142e-09 |

## Timing

| stage | cpu_ms | gpu_ms |
| --- | ---: | ---: |
| pulse_compression | 14.954494 | 3.277214 |
| pulse_doppler | 34.598568 | 1.884298 |
| power_map | 0.263471 | 0.196561 |
| ca_cfar | 1.817408 | 0.966894 |
| ambgfun | 21.126991 | 0.936205 |
| total | 72.760933 | 7.261172 |

## Validation

- pass: `true`
- repeat_runs: `3`
- cuda_free_delta_mib: `-160.000`
- rss_current_delta_mib: `444.098`

## Artifacts

- inputs: `data/generated/demo/task1_radar/input/`
- samples: `data/generated/demo/task1_radar/output_samples/`
- metrics: `data/reports/demo/task1_radar/latest_metrics.json`
- timings: `data/reports/demo/task1_radar/latest_stage_timings.csv`
- figures: run `python3 demo/task1_radar/visualize_task1.py`
