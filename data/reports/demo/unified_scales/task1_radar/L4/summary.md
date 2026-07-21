# Task 1 Radar Demo

## Scenario

- scale_level: `L4`
- scale_value: `131072`
- fs: `1e+06`
- num_pulses: `64`
- samples_per_pulse: `2048`
- template_length: `1024`
- prf: `2000`
- delay_samples: `384`
- doppler_hz: `125`
- snr_db: `20`

## Detection

| backend | found | range_bin | doppler_bin | doppler_hz | power |
| --- | --- | ---: | ---: | ---: | ---: |
| expected | true | 384 | 72 | 125.000 | 1016064.000 |
| cpu | true | 384 | 72 | 125.000 | 1016575.688 |
| gpu | true | 384 | 72 | 125.000 | 1016575.750 |

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| pulse_compression | 6.237485e-06 | 6.942854e-06 | 6.471027e+02 | 4.401463e-07 |
| pulse_doppler | 1.128869e-04 | 1.596808e-04 | 4.777155e+03 | 2.295601e-06 |
| cfar_threshold | 1.841278e-01 | 1.841278e-01 | 6.697512e+10 | 1.041408e-02 |
| ambgfun_surface | 3.650064e-06 | 1.788139e-07 | 1.935372e+01 | 3.913149e-09 |

## Timing

| stage | cpu_ms | gpu_ms | gpu_kernel_ms |
| --- | ---: | ---: | ---: |
| input_construction | 39.404610 | 1.065992 | 1.034728 |
| pulse_compression | 10.146789 | 0.873761 | 0.839342 |
| pulse_doppler | 72.267891 | 1.309803 | 1.274060 |
| power_map | 0.572741 | 0.190990 | 0.154714 |
| ca_cfar | 1.963504 | 1.210613 | 1.145786 |
| ambgfun | 106.920288 | 3.058586 | 3.023260 |
| final_detection | 0.944242 | 0.206270 | 0.169780 |
| total | 232.220062 | 7.916016 | 7.641670 |

## Validation

- pass: `true`
- repeat_runs: `7`
- gpu_free_delta_mib: `-192.000`
- rss_current_delta_mib: `505.398`

## Artifacts

- inputs: `data/generated/demo/task1_radar/input/`
- samples: `data/generated/demo/task1_radar/output_samples/`
- metrics: `data/.reports_staging/demo/task1_radar/latest_metrics.json`
- timings: `data/.reports_staging/demo/task1_radar/latest_stage_timings.csv`
