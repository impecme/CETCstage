# Task 1 Radar Demo

## Scenario

- scale_level: `L2`
- scale_value: `49152`
- fs: `1e+06`
- num_pulses: `32`
- samples_per_pulse: `1536`
- template_length: `1024`
- prf: `2000`
- delay_samples: `288`
- doppler_hz: `125`
- snr_db: `20`

## Detection

| backend | found | range_bin | doppler_bin | doppler_hz | power |
| --- | --- | ---: | ---: | ---: | ---: |
| expected | true | 288 | 72 | 125.000 | 246015.969 |
| cpu | true | 288 | 72 | 125.000 | 246129.953 |
| gpu | true | 288 | 72 | 125.000 | 246129.922 |

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| pulse_compression | 4.628657e-06 | 6.419586e-06 | 4.253720e+02 | 4.105984e-07 |
| pulse_doppler | 6.578938e-05 | 7.516502e-05 | 1.085943e+03 | 1.554727e-06 |
| cfar_threshold | 8.796263e-02 | 8.796263e-02 | 2.511567e+10 | 5.430972e-03 |
| ambgfun_surface | 3.650064e-06 | 1.788139e-07 | 1.935372e+01 | 3.913149e-09 |

## Timing

| stage | cpu_ms | gpu_ms | gpu_kernel_ms |
| --- | ---: | ---: | ---: |
| input_construction | 14.685972 | 0.551157 | 0.517804 |
| pulse_compression | 5.044562 | 0.919291 | 0.879860 |
| pulse_doppler | 68.461334 | 1.211515 | 1.169382 |
| power_map | 0.274563 | 0.199862 | 0.160948 |
| ca_cfar | 1.380837 | 1.203805 | 1.164886 |
| ambgfun | 103.040062 | 3.104808 | 3.064592 |
| final_detection | 1.140164 | 0.229483 | 0.190352 |
| total | 194.027496 | 7.419921 | 7.147824 |

## Validation

- pass: `true`
- repeat_runs: `7`
- gpu_free_delta_mib: `-176.000`
- rss_current_delta_mib: `496.250`

## Artifacts

- inputs: `data/generated/demo/task1_radar/input/`
- samples: `data/generated/demo/task1_radar/output_samples/`
- metrics: `data/.reports_staging/demo/task1_radar/latest_metrics.json`
- timings: `data/.reports_staging/demo/task1_radar/latest_stage_timings.csv`
