# task1_radar Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| pulse_compression | radartools/pulse_compression | 15.1448 | 1.10534 | 1.01139 | 6.60794e-06 | PASS |
| pulse_doppler | radartools/pulse_doppler_shifted | 70.6267 | 1.44147 | 1.40716 | 0.000140938 | PASS |
| power_map | radartools/power_map | 0.273261 | 0.188441 | 0.153606 | 0.0136719 | PASS |
| ca_cfar | radartools/ca_cfar | 1.42102 | 1.18579 | 1.14964 | 0.159197 | PASS |
| ambgfun | radartools/ambgfun | 107.454 | 3.08291 | 3.0476 | 3.65006e-06 | PASS |
| final_detection | radartools/detect_peak | 0.3191 | 0.200891 | 0.16528 | 0 | PASS |
