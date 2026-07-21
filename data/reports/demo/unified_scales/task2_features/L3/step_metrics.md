# task2_features Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| filter | filter_design/firwin + filtering/firfilter public complex64 path | 10.8155 | 0.959702 | 0.939304 | 3.38984e-06 | PASS |
| demod | demod/fm_demod + private batched score | 3.65862 | 0.16366 | 0.12739 | 0.000245506 | PASS |
| correlate | correlate/correlate + private normalization | 2309.69 | 2.0844 | 2.01439 | 6.51443e-06 | PASS |
| spectrogram | spectral/spectrogram + private band score | 15.2095 | 2.00845 | 1.94453 | 8.9981e-07 | PASS |
| cwt | wavelets/cwt + private scale reduction | 1142.8 | 3.27514 | 3.20216 | 1.78524e-06 | PASS |
| feature_fusion | private weighted fusion + peak selection | 0.54485 | 0.24651 | 0.219124 | 6.1797e-05 | PASS |
| measurement_conversion | estimation measurement helper | 0.0001 | 0 | 0 | 0 | PASS |
| kalman | estimation/kalman_filter + private GPU pipeline | 0.0675 | 0.09293 | 0.057216 | 0 | PASS |
