# task1_radar Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| pulse_compression | radartools/pulse_compression | 10.1468 | 0.873761 | 0.839342 | 6.23748e-06 | PASS |
| pulse_doppler | radartools/pulse_doppler_shifted | 72.2679 | 1.3098 | 1.27406 | 0.000112887 | PASS |
| power_map | radartools/power_map | 0.572741 | 0.19099 | 0.154714 | 0.00585938 | PASS |
| ca_cfar | radartools/ca_cfar | 1.9635 | 1.21061 | 1.14579 | 0.184128 | PASS |
| ambgfun | radartools/ambgfun | 106.92 | 3.05859 | 3.02326 | 3.65006e-06 | PASS |
| final_detection | radartools/detect_peak | 0.944242 | 0.20627 | 0.16978 | 6.14809e-08 | PASS |
