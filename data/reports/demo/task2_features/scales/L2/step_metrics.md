# task2_features Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| filter | filter_design/firwin + filtering/firfilter public complex64 path | 5.48907 | 0.640921 | 0.605226 | 2.5302e-06 | PASS |
| demod | demod/fm_demod + private batched score | 1.83742 | 0.16309 | 0.12273 | 0.000245506 | PASS |
| correlate | correlate/correlate + private normalization | 1158.2 | 1.28471 | 1.2182 | 6.51443e-06 | PASS |
| spectrogram | spectral/spectrogram + private band score | 7.68993 | 1.24194 | 1.18247 | 8.51164e-07 | PASS |
| cwt | wavelets/cwt + private scale reduction | 570.926 | 1.7925 | 1.73541 | 1.41813e-06 | PASS |
| feature_fusion | private weighted fusion + peak selection | 0.27353 | 0.21804 | 0.182152 | 2.36797e-05 | PASS |
| measurement_conversion | estimation measurement helper | 8e-05 | 0 | 0 | 0 | PASS |
| kalman | estimation/kalman_filter + private GPU pipeline | 0.04794 | 0.09679 | 0.05931 | 0 | PASS |
