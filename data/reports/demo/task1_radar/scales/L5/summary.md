# Task 1 Radar Demo

## Scenario

- scale_level: `L5`
- scale_value: `294912`
- fs: `1e+06`
- num_pulses: `96`
- samples_per_pulse: `3072`
- template_length: `1024`
- prf: `2000`
- delay_samples: `576`
- doppler_hz: `125`
- snr_db: `20`

## Detection

| backend | found | range_bin | doppler_bin | doppler_hz | power |
| --- | --- | ---: | ---: | ---: | ---: |
| expected | true | 576 | 72 | 125.000 | 2310399.750 |
| cpu | true | 576 | 72 | 125.000 | 2310126.750 |
| gpu | true | 576 | 72 | 125.000 | 2310126.750 |

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| pulse_compression | 6.607939e-06 | 8.092195e-06 | 2.755772e+01 | 4.147400e-07 |
| pulse_doppler | 1.409377e-04 | 3.452670e-04 | 7.915649e+01 | 2.673960e-06 |
| cfar_threshold | 1.591967e-01 | 1.591967e-01 | 5.023134e+10 | 1.316985e-02 |
| ambgfun_surface | 3.650064e-06 | 1.788139e-07 | 1.935372e+01 | 3.913149e-09 |

## Timing

| stage | cpu_ms | gpu_ms | gpu_kernel_ms |
| --- | ---: | ---: | ---: |
| input_construction | 87.475601 | 5.336263 | 5.294404 |
| pulse_compression | 15.014480 | 1.078441 | 1.038508 |
| pulse_doppler | 69.930954 | 1.454568 | 1.414692 |
| power_map | 0.168203 | 0.194854 | 0.157706 |
| ca_cfar | 1.442288 | 1.244204 | 1.205022 |
| ambgfun | 107.155785 | 3.057769 | 3.020018 |
| final_detection | 0.901528 | 0.228604 | 0.189716 |
| total | 282.088837 | 12.594704 | 12.320066 |

## Validation

- pass: `true`
- repeat_runs: `7`
- gpu_free_delta_mib: `-192.000`
- rss_current_delta_mib: `516.156`

## Artifacts

- inputs: `data/generated/demo/task1_radar/input/`
- samples: `data/generated/demo/task1_radar/output_samples/`
- metrics: `data/.reports_staging/demo/task1_radar/latest_metrics.json`
- timings: `data/.reports_staging/demo/task1_radar/latest_stage_timings.csv`
