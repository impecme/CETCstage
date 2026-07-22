# task2_features Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| filter | filter_design/firwin + filtering/firfilter public complex64 path | 2.7956 | 0.636877 | 0.604438 | 2.5302e-06 | PASS |
| demod | demod/fm_demod + private batched score | 0.922801 | 0.186312 | 0.14862 | 6.71085e-05 | PASS |
| correlate | correlate/correlate + private normalization | 606.964 | 0.780849 | 0.709024 | 6.51443e-06 | PASS |
| spectrogram | spectral/spectrogram + private band score | 3.87561 | 0.914881 | 0.819094 | 9.28071e-07 | PASS |
| cwt | wavelets/cwt + private scale reduction | 282.581 | 1.09335 | 1.01641 | 1.45757e-06 | PASS |
| feature_fusion | private weighted fusion + peak selection | 0.137412 | 0.214593 | 0.176024 | 2.27624e-05 | PASS |
| measurement_conversion | estimation measurement helper | 8e-05 | 0 | 0 | 0 | PASS |
| kalman | estimation/kalman_filter + private GPU pipeline | 0.043741 | 0.103281 | 0.07008 | 0 | PASS |
