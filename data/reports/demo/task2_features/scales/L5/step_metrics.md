# task2_features Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| filter | filter_design/firwin + filtering/firfilter public complex64 path | 33.463 | 1.94391 | 1.92519 | 4.07773e-06 | PASS |
| demod | demod/fm_demod + private batched score | 11.0401 | 0.247855 | 0.21672 | 0.000245506 | PASS |
| correlate | correlate/correlate + private normalization | 7147.43 | 1.76006 | 1.69775 | 9.29532e-06 | PASS |
| spectrogram | spectral/spectrogram + private band score | 46.0328 | 2.96595 | 2.89946 | 9.13948e-07 | PASS |
| cwt | wavelets/cwt + private scale reduction | 3391.85 | 9.59157 | 9.51903 | 1.80458e-06 | PASS |
| feature_fusion | private weighted fusion + peak selection | 1.64327 | 0.620103 | 0.571956 | 9.83703e-05 | PASS |
| measurement_conversion | estimation measurement helper | 0.00048 | 0 | 0 | 0 | PASS |
| kalman | estimation/kalman_filter + private GPU pipeline | 0.128313 | 0.117253 | 0.075606 | 0 | PASS |
