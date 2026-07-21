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
| input_construction | 29.752476 | 0.581861 | 0.548000 |
| pulse_compression | 7.565182 | 0.936331 | 0.900420 |
| pulse_doppler | 67.915405 | 1.240962 | 1.204004 |
| power_map | 0.163551 | 0.191720 | 0.158208 |
| ca_cfar | 1.346432 | 1.176922 | 1.142458 |
| ambgfun | 102.937210 | 3.038945 | 3.002966 |
| final_detection | 0.952922 | 0.202000 | 0.168104 |
| total | 210.633194 | 7.368742 | 7.124160 |

## Validation

- pass: `true`
- repeat_runs: `7`
- gpu_free_delta_mib: `-192.000`
- rss_current_delta_mib: `493.145`

## Artifacts

- inputs: `data/generated/demo/task1_radar/input/`
- samples: `data/generated/demo/task1_radar/output_samples/`
- metrics: `data/.reports_staging/demo/task1_radar/latest_metrics.json`
- timings: `data/.reports_staging/demo/task1_radar/latest_stage_timings.csv`
