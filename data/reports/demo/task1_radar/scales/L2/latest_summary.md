# Task 1 Radar Demo

## Scenario

- scale_level: `L2`
- scale_value: `12288`
- fs: `1e+06`
- num_pulses: `48`
- samples_per_pulse: `256`
- template_length: `64`
- prf: `2000`
- delay_samples: `48`
- doppler_hz: `125`
- snr_db: `20`

## Detection

| backend | found | range_bin | doppler_bin | doppler_hz | power |
| --- | --- | ---: | ---: | ---: | ---: |
| expected | true | 48 | 36 | 125.000 | 35343.996 |
| cpu | true | 48 | 36 | 125.000 | 35375.016 |
| gpu | true | 48 | 36 | 125.000 | 35375.027 |

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| pulse_compression | 1.087230e-05 | 2.567847e-06 | 5.598114e-04 | 3.866116e-07 |
| pulse_doppler | 2.034204e-05 | 3.269862e-05 | 2.642806e-04 | 1.689354e-06 |
| cfar_threshold | 2.113342e-03 | 3.417969e-03 | 1.935958e-03 | 3.885315e-04 |
| ambgfun_surface | 8.173051e-06 | 1.490116e-07 | 1.388860e+01 | 1.164671e-08 |

## Timing

| stage | cpu_ms | gpu_ms |
| --- | ---: | ---: |
| pulse_compression | 1.030125 | 0.736503 |
| pulse_doppler | 1.840117 | 0.700002 |
| power_map | 0.005320 | 0.104561 |
| ca_cfar | 0.032610 | 0.273091 |
| ambgfun | 2.192248 | 0.455121 |
| total | 5.100420 | 2.269278 |

## Validation

- pass: `true`
- repeat_runs: `3`
- cuda_free_delta_mib: `-112.000`
- rss_current_delta_mib: `362.066`

## Artifacts

- inputs: `data/generated/demo/task1_radar/input/`
- samples: `data/generated/demo/task1_radar/output_samples/`
- metrics: `data/reports/demo/task1_radar/latest_metrics.json`
- timings: `data/reports/demo/task1_radar/latest_stage_timings.csv`
- figures: run `python3 demo/task1_radar/visualize_task1.py`
