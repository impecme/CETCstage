# task2_features Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| filter | filter_design/firwin + filtering/firfilter public complex64 path | 2.70316 | 0.38224 | 0.35198 | 2.5302e-06 | PASS |
| demod | demod/fm_demod + private batched score | 0.910511 | 0.12707 | 0.091962 | 6.71085e-05 | PASS |
| correlate | correlate/correlate + private normalization | 582.743 | 0.718611 | 0.65152 | 6.51443e-06 | PASS |
| spectrogram | spectral/spectrogram + private band score | 3.82108 | 0.75717 | 0.693656 | 9.28071e-07 | PASS |
| cwt | wavelets/cwt + private scale reduction | 309.971 | 0.985931 | 0.921814 | 1.45757e-06 | PASS |
| feature_fusion | private weighted fusion + peak selection | 0.13608 | 0.17681 | 0.150994 | 2.27624e-05 | PASS |
| measurement_conversion | estimation measurement helper | 9e-05 | 0 | 0 | 0 | PASS |
| kalman | estimation/kalman_filter + private GPU pipeline | 0.0374 | 0.08331 | 0.04919 | 0 | PASS |
