# task2_features Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| filter | filter_design/firwin + filtering/firfilter public complex64 path | 22.246 | 1.50956 | 1.48658 | 3.35682e-06 | PASS |
| demod | demod/fm_demod + private batched score | 7.3547 | 0.208784 | 0.174744 | 0.000245506 | PASS |
| correlate | correlate/correlate + private normalization | 4755.05 | 1.3338 | 1.27133 | 7.83549e-06 | PASS |
| spectrogram | spectral/spectrogram + private band score | 30.5994 | 2.10166 | 2.04056 | 1.06843e-06 | PASS |
| cwt | wavelets/cwt + private scale reduction | 2259.94 | 6.34099 | 6.27451 | 1.29036e-06 | PASS |
| feature_fusion | private weighted fusion + peak selection | 1.10281 | 0.402648 | 0.37546 | 9.83703e-05 | PASS |
| measurement_conversion | estimation measurement helper | 0.00012 | 0 | 0 | 0 | PASS |
| kalman | estimation/kalman_filter + private GPU pipeline | 0.113032 | 0.096512 | 0.064022 | 0 | PASS |
