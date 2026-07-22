# task2_features Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| filter | filter_design/firwin + filtering/firfilter public complex64 path | 10.7358 | 0.913525 | 0.87566 | 3.38984e-06 | PASS |
| demod | demod/fm_demod + private batched score | 3.68242 | 0.196313 | 0.149524 | 0.000245506 | PASS |
| correlate | correlate/correlate + private normalization | 2357.65 | 2.13612 | 2.0718 | 6.51443e-06 | PASS |
| spectrogram | spectral/spectrogram + private band score | 15.2194 | 1.9854 | 1.92579 | 8.9981e-07 | PASS |
| cwt | wavelets/cwt + private scale reduction | 1129.23 | 3.34857 | 3.28213 | 1.78524e-06 | PASS |
| feature_fusion | private weighted fusion + peak selection | 0.546045 | 0.240974 | 0.217548 | 6.1797e-05 | PASS |
| measurement_conversion | estimation measurement helper | 0.00034 | 0 | 0 | 0 | PASS |
| kalman | estimation/kalman_filter + private GPU pipeline | 0.071781 | 0.081621 | 0.059912 | 0 | PASS |
