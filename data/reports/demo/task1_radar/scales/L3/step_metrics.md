# task1_radar Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| pulse_compression | radartools/pulse_compression | 7.73227 | 0.920473 | 0.874576 | 6.23748e-06 | PASS |
| pulse_doppler | radartools/pulse_doppler_shifted | 69.6577 | 1.30229 | 1.25746 | 8.09962e-05 | PASS |
| power_map | radartools/power_map | 0.169313 | 0.217783 | 0.173888 | 0.00341797 | PASS |
| ca_cfar | radartools/ca_cfar | 1.98083 | 1.24764 | 1.19605 | 0.102474 | PASS |
| ambgfun | radartools/ambgfun | 102.385 | 3.10315 | 3.05506 | 3.65006e-06 | PASS |
| final_detection | radartools/detect_peak | 1.0652 | 0.253294 | 0.20559 | 1.10487e-07 | PASS |
