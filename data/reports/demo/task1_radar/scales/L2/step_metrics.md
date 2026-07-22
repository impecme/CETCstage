# task1_radar Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| pulse_compression | radartools/pulse_compression | 5.04456 | 0.919291 | 0.87986 | 4.62866e-06 | PASS |
| pulse_doppler | radartools/pulse_doppler_shifted | 68.4613 | 1.21151 | 1.16938 | 6.57894e-05 | PASS |
| power_map | radartools/power_map | 0.274563 | 0.199862 | 0.160948 | 0.00195312 | PASS |
| ca_cfar | radartools/ca_cfar | 1.38084 | 1.2038 | 1.16489 | 0.0879626 | PASS |
| ambgfun | radartools/ambgfun | 103.04 | 3.10481 | 3.06459 | 3.65006e-06 | PASS |
| final_detection | radartools/detect_peak | 1.14016 | 0.229483 | 0.190352 | 1.26965e-07 | PASS |
