# Task 1 Radar Demo

## Scenario

- scale_level: `L3`
- scale_value: `98304`
- fs: `1e+06`
- num_pulses: `48`
- samples_per_pulse: `2048`
- template_length: `1024`
- prf: `2000`
- delay_samples: `384`
- doppler_hz: `125`
- snr_db: `20`

## Detection

| backend | found | range_bin | doppler_bin | doppler_hz | power |
| --- | --- | ---: | ---: | ---: | ---: |
| expected | true | 384 | 72 | 125.000 | 565503.938 |
| cpu | true | 384 | 72 | 125.000 | 565676.312 |
| gpu | true | 384 | 72 | 125.000 | 565676.250 |

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| pulse_compression | 6.237485e-06 | 6.942854e-06 | 6.471027e+02 | 4.398667e-07 |
| pulse_doppler | 8.099622e-05 | 1.525879e-04 | 1.198746e+03 | 2.000894e-06 |
| cfar_threshold | 1.024740e-01 | 1.024740e-01 | 2.092972e+10 | 7.465712e-03 |
| ambgfun_surface | 3.650064e-06 | 1.788139e-07 | 1.935372e+01 | 3.913149e-09 |

## Timing

| stage | cpu_ms | gpu_ms | gpu_kernel_ms |
| --- | ---: | ---: | ---: |
| input_construction | 29.578220 | 0.783921 | 0.739920 |
| pulse_compression | 7.732269 | 0.920473 | 0.874576 |
| pulse_doppler | 69.657745 | 1.302288 | 1.257460 |
| power_map | 0.169313 | 0.217783 | 0.173888 |
| ca_cfar | 1.980828 | 1.247638 | 1.196046 |
| ambgfun | 102.384598 | 3.103154 | 3.055058 |
| final_detection | 1.065205 | 0.253294 | 0.205590 |
| total | 212.568161 | 7.828551 | 7.502538 |

## Validation

- pass: `true`
- repeat_runs: `7`
- gpu_free_delta_mib: `-192.000`
- rss_current_delta_mib: `492.879`

## Artifacts

- inputs: `data/generated/demo/task1_radar/input/`
- samples: `data/generated/demo/task1_radar/output_samples/`
- metrics: `data/.reports_staging/demo/task1_radar/latest_metrics.json`
- timings: `data/.reports_staging/demo/task1_radar/latest_stage_timings.csv`
