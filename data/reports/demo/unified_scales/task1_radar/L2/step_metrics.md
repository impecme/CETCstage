# task1_radar Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| pulse_compression | radartools/pulse_compression | 5.20973 | 0.798451 | 0.761406 | 4.62866e-06 | PASS |
| pulse_doppler | radartools/pulse_doppler_shifted | 67.0788 | 1.20697 | 1.17139 | 6.57894e-05 | PASS |
| power_map | radartools/power_map | 0.26939 | 0.19254 | 0.158412 | 0.00195312 | PASS |
| ca_cfar | radartools/ca_cfar | 1.39533 | 1.18314 | 1.14893 | 0.0879626 | PASS |
| ambgfun | radartools/ambgfun | 102.816 | 3.08453 | 3.04665 | 3.65006e-06 | PASS |
| final_detection | radartools/detect_peak | 1.13338 | 0.21333 | 0.179068 | 1.26965e-07 | PASS |
