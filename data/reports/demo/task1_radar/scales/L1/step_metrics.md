# task1_radar Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| pulse_compression | radartools/pulse_compression | 2.7114 | 0.738358 | 0.694684 | 4.62e-06 | PASS |
| pulse_doppler | radartools/pulse_doppler_shifted | 68.5346 | 1.16638 | 1.12853 | 3.11573e-05 | PASS |
| power_map | radartools/power_map | 0.253283 | 0.200002 | 0.161434 | 0.000488281 | PASS |
| ca_cfar | radartools/ca_cfar | 1.34189 | 1.20939 | 1.16797 | 0.0455225 | PASS |
| ambgfun | radartools/ambgfun | 106.938 | 3.12048 | 3.08022 | 3.65006e-06 | PASS |
| final_detection | radartools/detect_peak | 1.07654 | 0.234053 | 0.173124 | 1.35689e-07 | PASS |
