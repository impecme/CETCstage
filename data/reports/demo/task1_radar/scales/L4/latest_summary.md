# Task 1 Radar Demo

## Scenario

- scale_level: `L4`
- scale_value: `49152`
- fs: `1e+06`
- num_pulses: `96`
- samples_per_pulse: `512`
- template_length: `128`
- prf: `2000`
- delay_samples: `96`
- doppler_hz: `125`
- snr_db: `20`

## Detection

| backend | found | range_bin | doppler_bin | doppler_hz | power |
| --- | --- | ---: | ---: | ---: | ---: |
| expected | true | 96 | 72 | 125.000 | 288799.969 |
| cpu | true | 96 | 72 | 125.000 | 288540.844 |
| gpu | true | 96 | 72 | 125.000 | 288540.844 |

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| pulse_compression | 1.042766e-05 | 2.384186e-06 | 5.687362e-04 | 3.414763e-07 |
| pulse_doppler | 5.007390e-05 | 6.823938e-05 | 5.307219e-04 | 2.260404e-06 |
| cfar_threshold | 2.089691e-02 | 2.089691e-02 | 6.733999e-03 | 1.813888e-03 |
| ambgfun_surface | 8.874485e-06 | 1.788139e-07 | 6.213629e+00 | 9.470174e-09 |

## Timing

| stage | cpu_ms | gpu_ms |
| --- | ---: | ---: |
| pulse_compression | 2.906912 | 0.835774 |
| pulse_doppler | 9.644950 | 0.755363 |
| power_map | 0.020090 | 0.126980 |
| ca_cfar | 0.197540 | 0.378492 |
| ambgfun | 2.999923 | 0.502922 |
| total | 15.769415 | 2.599531 |

## Validation

- pass: `true`
- repeat_runs: `3`
- cuda_free_delta_mib: `-112.000`
- rss_current_delta_mib: `367.918`

## Artifacts

- inputs: `data/generated/demo/task1_radar/input/`
- samples: `data/generated/demo/task1_radar/output_samples/`
- metrics: `data/reports/demo/task1_radar/latest_metrics.json`
- timings: `data/reports/demo/task1_radar/latest_stage_timings.csv`
- figures: run `python3 demo/task1_radar/visualize_task1.py`
