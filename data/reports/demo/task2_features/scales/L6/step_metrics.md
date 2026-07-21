# task2_features Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| filter | filter_design/firwin + filtering/firfilter public complex64 path | 43.345 | 2.45891 | 2.4356 | 4.0939e-06 | PASS |
| demod | demod/fm_demod + private batched score | 14.7338 | 0.295831 | 0.259214 | 0.000466782 | PASS |
| correlate | correlate/correlate + private normalization | 9341.38 | 2.21868 | 2.15098 | 9.29532e-06 | PASS |
| spectrogram | spectral/spectrogram + private band score | 61.4018 | 3.77345 | 3.70087 | 1.05161e-06 | PASS |
| cwt | wavelets/cwt + private scale reduction | 4575.52 | 12.5127 | 12.4517 | 1.81284e-06 | PASS |
| feature_fusion | private weighted fusion + peak selection | 2.18783 | 0.727583 | 0.70246 | 9.83703e-05 | PASS |
| measurement_conversion | estimation measurement helper | 0.00029 | 0 | 0 | 0 | PASS |
| kalman | estimation/kalman_filter + private GPU pipeline | 0.188151 | 0.10229 | 0.078494 | 0 | PASS |
