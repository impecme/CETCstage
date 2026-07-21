# task1_radar Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| pulse_compression | radartools/pulse_compression | 2.69048 | 0.79132 | 0.745356 | 4.62e-06 | PASS |
| pulse_doppler | radartools/pulse_doppler_shifted | 66.9845 | 1.14941 | 1.10736 | 3.11573e-05 | PASS |
| power_map | radartools/power_map | 0.279291 | 0.199761 | 0.162428 | 0.000488281 | PASS |
| ca_cfar | radartools/ca_cfar | 1.3821 | 1.20469 | 1.16572 | 0.0455225 | PASS |
| ambgfun | radartools/ambgfun | 107.32 | 3.05726 | 3.01455 | 3.65006e-06 | PASS |
| final_detection | radartools/detect_peak | 0.964191 | 0.21528 | 0.179468 | 1.35689e-07 | PASS |
