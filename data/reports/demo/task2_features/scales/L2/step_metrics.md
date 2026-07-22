# task2_features Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| filter | filter_design/firwin + filtering/firfilter public complex64 path | 5.48224 | 0.625959 | 0.592812 | 2.5302e-06 | PASS |
| demod | demod/fm_demod + private batched score | 1.83459 | 0.172172 | 0.131668 | 0.000245506 | PASS |
| correlate | correlate/correlate + private normalization | 1209.98 | 1.2016 | 1.13223 | 6.51443e-06 | PASS |
| spectrogram | spectral/spectrogram + private band score | 7.63852 | 1.22661 | 1.13763 | 8.51164e-07 | PASS |
| cwt | wavelets/cwt + private scale reduction | 564.801 | 1.86468 | 1.78352 | 1.41813e-06 | PASS |
| feature_fusion | private weighted fusion + peak selection | 0.272523 | 0.220353 | 0.18886 | 2.36797e-05 | PASS |
| measurement_conversion | estimation measurement helper | 0.0001 | 0 | 0 | 0 | PASS |
| kalman | estimation/kalman_filter + private GPU pipeline | 0.048451 | 0.094361 | 0.06577 | 0 | PASS |
