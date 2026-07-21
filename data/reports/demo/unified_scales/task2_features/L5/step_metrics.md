# task2_features Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| filter | filter_design/firwin + filtering/firfilter public complex64 path | 32.7873 | 1.98269 | 1.96901 | 4.07773e-06 | PASS |
| demod | demod/fm_demod + private batched score | 11.0455 | 0.270521 | 0.231362 | 0.000245506 | PASS |
| correlate | correlate/correlate + private normalization | 6966.49 | 1.78726 | 1.72422 | 9.29532e-06 | PASS |
| spectrogram | spectral/spectrogram + private band score | 45.7523 | 2.97771 | 2.91045 | 9.13948e-07 | PASS |
| cwt | wavelets/cwt + private scale reduction | 3721.77 | 9.54755 | 9.48247 | 1.80458e-06 | PASS |
| feature_fusion | private weighted fusion + peak selection | 1.64942 | 0.580372 | 0.55046 | 9.83703e-05 | PASS |
| measurement_conversion | estimation measurement helper | 0.0002 | 0 | 0 | 0 | PASS |
| kalman | estimation/kalman_filter + private GPU pipeline | 0.14603 | 0.10013 | 0.074678 | 0 | PASS |
