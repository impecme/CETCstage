# task1_radar Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| pulse_compression | radartools/pulse_compression | 10.0354 | 0.910135 | 0.874752 | 6.23748e-06 | PASS |
| pulse_doppler | radartools/pulse_doppler_shifted | 69.8076 | 1.36403 | 1.32389 | 0.000112887 | PASS |
| power_map | radartools/power_map | 0.282725 | 0.198934 | 0.162308 | 0.00585938 | PASS |
| ca_cfar | radartools/ca_cfar | 1.35756 | 1.18949 | 1.15257 | 0.184128 | PASS |
| ambgfun | radartools/ambgfun | 107.567 | 3.08534 | 3.04488 | 3.65006e-06 | PASS |
| final_detection | radartools/detect_peak | 0.459898 | 0.215304 | 0.175576 | 6.14809e-08 | PASS |
