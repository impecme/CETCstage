# task1_radar Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| pulse_compression | radartools/pulse_compression | 15.0145 | 1.07844 | 1.03851 | 6.60794e-06 | PASS |
| pulse_doppler | radartools/pulse_doppler_shifted | 69.931 | 1.45457 | 1.41469 | 0.000140938 | PASS |
| power_map | radartools/power_map | 0.168203 | 0.194854 | 0.157706 | 0.0136719 | PASS |
| ca_cfar | radartools/ca_cfar | 1.44229 | 1.2442 | 1.20502 | 0.159197 | PASS |
| ambgfun | radartools/ambgfun | 107.156 | 3.05777 | 3.02002 | 3.65006e-06 | PASS |
| final_detection | radartools/detect_peak | 0.901528 | 0.228604 | 0.189716 | 0 | PASS |
