# task1_radar Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| pulse_compression | radartools/pulse_compression | 22.4861 | 1.48971 | 1.4433 | 6.85978e-06 | PASS |
| pulse_doppler | radartools/pulse_doppler_shifted | 74.8429 | 1.6733 | 1.62544 | 0.000163502 | PASS |
| power_map | radartools/power_map | 0.279846 | 0.243856 | 0.194704 | 0.03125 | PASS |
| ca_cfar | radartools/ca_cfar | 1.28692 | 1.26474 | 1.21686 | 0.276398 | PASS |
| ambgfun | radartools/ambgfun | 111.132 | 3.22964 | 3.18144 | 3.65006e-06 | PASS |
| final_detection | radartools/detect_peak | 0.405319 | 0.301786 | 0.244538 | 1.20988e-07 | PASS |
