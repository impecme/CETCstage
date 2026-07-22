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
| input_construction | 38.858368 | 0.745913 | 0.715220 |
| pulse_compression | 10.035415 | 0.910135 | 0.874752 |
| pulse_doppler | 69.807571 | 1.364032 | 1.323894 |
| power_map | 0.282725 | 0.198934 | 0.162308 |
| ca_cfar | 1.357562 | 1.189489 | 1.152574 |
| ambgfun | 107.567352 | 3.085340 | 3.044880 |
| final_detection | 0.459898 | 0.215304 | 0.175576 |
| total | 228.368896 | 7.709147 | 7.449204 |

## Validation

- pass: `true`
- repeat_runs: `7`
- gpu_free_delta_mib: `-192.000`
- rss_current_delta_mib: `505.602`

## Artifacts

- inputs: `data/generated/demo/task1_radar/input/`
- samples: `data/generated/demo/task1_radar/output_samples/`
- metrics: `data/.reports_staging/demo/task1_radar/latest_metrics.json`
- timings: `data/.reports_staging/demo/task1_radar/latest_stage_timings.csv`
