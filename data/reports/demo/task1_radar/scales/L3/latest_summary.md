# Task 1 Radar Demo

## Scenario

- scale_level: `L3`
- scale_value: `16384`
- fs: `1e+06`
- num_pulses: `64`
- samples_per_pulse: `256`
- template_length: `64`
- prf: `2000`
- delay_samples: `48`
- doppler_hz: `125`
- snr_db: `20`

## Detection

| backend | found | range_bin | doppler_bin | doppler_hz | power |
| --- | --- | ---: | ---: | ---: | ---: |
| expected | true | 48 | 36 | 125.000 | 63504.000 |
| cpu | true | 48 | 36 | 125.000 | 63662.328 |
| gpu | true | 48 | 36 | 125.000 | 63662.352 |

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| pulse_compression | 1.087230e-05 | 2.567847e-06 | 5.598114e-04 | 3.858765e-07 |
| pulse_doppler | 2.703851e-05 | 5.104695e-05 | 5.690427e-04 | 2.003310e-06 |
| cfar_threshold | 2.487183e-03 | 2.929688e-03 | 1.694153e-03 | 4.309557e-04 |
| ambgfun_surface | 8.173051e-06 | 1.490116e-07 | 1.388860e+01 | 1.164671e-08 |

## Timing

| stage | cpu_ms | gpu_ms |
| --- | ---: | ---: |
| pulse_compression | 1.347225 | 0.771373 |
| pulse_doppler | 1.844388 | 0.665093 |
| power_map | 0.005240 | 0.106580 |
| ca_cfar | 0.032740 | 0.273472 |
| ambgfun | 2.133388 | 0.457861 |
| total | 5.362981 | 2.274379 |

## Validation

- pass: `true`
- repeat_runs: `3`
- cuda_free_delta_mib: `-112.000`
- rss_current_delta_mib: `362.531`

## Artifacts

- inputs: `data/generated/demo/task1_radar/input/`
- samples: `data/generated/demo/task1_radar/output_samples/`
- metrics: `data/reports/demo/task1_radar/latest_metrics.json`
- timings: `data/reports/demo/task1_radar/latest_stage_timings.csv`
- figures: run `python3 demo/task1_radar/visualize_task1.py`
