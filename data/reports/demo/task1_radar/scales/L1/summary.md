# Task 1 Radar Demo

## Scenario

- scale_level: `L1`
- scale_value: `24576`
- fs: `1e+06`
- num_pulses: `16`
- samples_per_pulse: `1536`
- template_length: `1024`
- prf: `2000`
- delay_samples: `288`
- doppler_hz: `125`
- snr_db: `20`

## Detection

| backend | found | range_bin | doppler_bin | doppler_hz | power |
| --- | --- | ---: | ---: | ---: | ---: |
| expected | true | 288 | 72 | 125.000 | 57599.992 |
| cpu | true | 288 | 72 | 125.000 | 57576.434 |
| gpu | true | 288 | 72 | 125.000 | 57576.426 |

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| pulse_compression | 4.620003e-06 | 6.419586e-06 | 4.253720e+02 | 4.104457e-07 |
| pulse_doppler | 3.115725e-05 | 5.501635e-05 | 2.351942e+03 | 1.036681e-06 |
| cfar_threshold | 4.552245e-02 | 4.552245e-02 | 2.511567e+10 | 2.885671e-03 |
| ambgfun_surface | 3.650064e-06 | 1.788139e-07 | 1.935372e+01 | 3.913149e-09 |

## Timing

| stage | cpu_ms | gpu_ms | gpu_kernel_ms |
| --- | ---: | ---: | ---: |
| input_construction | 7.442661 | 0.344954 | 0.305998 |
| pulse_compression | 2.711399 | 0.738358 | 0.694684 |
| pulse_doppler | 68.534569 | 1.166383 | 1.128528 |
| power_map | 0.253283 | 0.200002 | 0.161434 |
| ca_cfar | 1.341894 | 1.209393 | 1.167974 |
| ambgfun | 106.938484 | 3.120484 | 3.080220 |
| final_detection | 1.076542 | 0.234053 | 0.173124 |
| total | 188.298828 | 7.013628 | 6.711962 |

## Validation

- pass: `true`
- repeat_runs: `7`
- gpu_free_delta_mib: `-176.000`
- rss_current_delta_mib: `489.797`

## Artifacts

- inputs: `data/generated/demo/task1_radar/input/`
- samples: `data/generated/demo/task1_radar/output_samples/`
- metrics: `data/.reports_staging/demo/task1_radar/latest_metrics.json`
- timings: `data/.reports_staging/demo/task1_radar/latest_stage_timings.csv`
