# task1_radar Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| pulse_compression | radartools/pulse_compression | 7.56518 | 0.936331 | 0.90042 | 6.23748e-06 | PASS |
| pulse_doppler | radartools/pulse_doppler_shifted | 67.9154 | 1.24096 | 1.204 | 8.09962e-05 | PASS |
| power_map | radartools/power_map | 0.163551 | 0.19172 | 0.158208 | 0.00341797 | PASS |
| ca_cfar | radartools/ca_cfar | 1.34643 | 1.17692 | 1.14246 | 0.102474 | PASS |
| ambgfun | radartools/ambgfun | 102.937 | 3.03894 | 3.00297 | 3.65006e-06 | PASS |
| final_detection | radartools/detect_peak | 0.952922 | 0.202 | 0.168104 | 1.10487e-07 | PASS |
