# Task 1 Radar Demo

## Scenario

- scale_level: `L6`
- scale_value: `524288`
- fs: `1e+06`
- num_pulses: `128`
- samples_per_pulse: `4096`
- template_length: `1024`
- prf: `2000`
- delay_samples: `768`
- doppler_hz: `125`
- snr_db: `20`

## Detection

| backend | found | range_bin | doppler_bin | doppler_hz | power |
| --- | --- | ---: | ---: | ---: | ---: |
| expected | true | 768 | 72 | 125.000 | 4129024.000 |
| cpu | true | 768 | 72 | 125.000 | 4132641.250 |
| gpu | true | 768 | 72 | 125.000 | 4132640.750 |

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| pulse_compression | 6.859777e-06 | 7.448435e-06 | 4.017607e-03 | 4.414798e-07 |
| pulse_doppler | 1.635025e-04 | 3.860202e-04 | 2.165461e-03 | 3.256778e-06 |
| cfar_threshold | 2.763977e-01 | 2.763977e-01 | 1.090031e-01 | 2.345303e-02 |
| ambgfun_surface | 3.650064e-06 | 1.788139e-07 | 1.935372e+01 | 3.913149e-09 |

## Timing

| stage | cpu_ms | gpu_ms | gpu_kernel_ms |
| --- | ---: | ---: | ---: |
| input_construction | 155.103149 | 3.163750 | 3.130718 |
| pulse_compression | 21.137411 | 1.257554 | 1.223508 |
| pulse_doppler | 71.181061 | 1.512064 | 1.479272 |
| power_map | 0.290451 | 0.177211 | 0.144016 |
| ca_cfar | 1.471654 | 1.226324 | 1.170430 |
| ambgfun | 110.577019 | 3.208109 | 3.173978 |
| final_detection | 0.315181 | 0.205971 | 0.169228 |
| total | 360.075928 | 10.750982 | 10.491149 |

## Validation

- pass: `true`
- repeat_runs: `7`
- gpu_free_delta_mib: `-192.000`
- rss_current_delta_mib: `520.496`

## Artifacts

- inputs: `data/generated/demo/task1_radar/input/`
- samples: `data/generated/demo/task1_radar/output_samples/`
- metrics: `data/.reports_staging/demo/task1_radar/latest_metrics.json`
- timings: `data/.reports_staging/demo/task1_radar/latest_stage_timings.csv`
