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
| input_construction | 164.425781 | 3.265843 | 3.222288 |
| pulse_compression | 22.486124 | 1.489714 | 1.443300 |
| pulse_doppler | 74.842926 | 1.673298 | 1.625436 |
| power_map | 0.279846 | 0.243856 | 0.194704 |
| ca_cfar | 1.286919 | 1.264739 | 1.216856 |
| ambgfun | 111.131981 | 3.229642 | 3.181436 |
| final_detection | 0.405319 | 0.301786 | 0.244538 |
| total | 374.858887 | 11.468878 | 11.128558 |

## Validation

- pass: `true`
- repeat_runs: `7`
- gpu_free_delta_mib: `-192.000`
- rss_current_delta_mib: `520.508`

## Artifacts

- inputs: `data/generated/demo/task1_radar/input/`
- samples: `data/generated/demo/task1_radar/output_samples/`
- metrics: `data/.reports_staging/demo/task1_radar/latest_metrics.json`
- timings: `data/.reports_staging/demo/task1_radar/latest_stage_timings.csv`
