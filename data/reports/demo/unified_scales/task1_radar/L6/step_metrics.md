# task1_radar Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| pulse_compression | radartools/pulse_compression | 21.1374 | 1.25755 | 1.22351 | 6.85978e-06 | PASS |
| pulse_doppler | radartools/pulse_doppler_shifted | 71.1811 | 1.51206 | 1.47927 | 0.000163502 | PASS |
| power_map | radartools/power_map | 0.290451 | 0.177211 | 0.144016 | 0.03125 | PASS |
| ca_cfar | radartools/ca_cfar | 1.47165 | 1.22632 | 1.17043 | 0.276398 | PASS |
| ambgfun | radartools/ambgfun | 110.577 | 3.20811 | 3.17398 | 3.65006e-06 | PASS |
| final_detection | radartools/detect_peak | 0.315181 | 0.205971 | 0.169228 | 1.20988e-07 | PASS |
