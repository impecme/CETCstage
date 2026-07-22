# task2_features Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| filter | filter_design/firwin + filtering/firfilter public complex64 path | 43.4232 | 2.37556 | 2.35487 | 4.0939e-06 | PASS |
| demod | demod/fm_demod + private batched score | 14.7435 | 0.302357 | 0.26443 | 0.000466782 | PASS |
| correlate | correlate/correlate + private normalization | 9490.3 | 2.19055 | 2.1272 | 9.29532e-06 | PASS |
| spectrogram | spectral/spectrogram + private band score | 61.4038 | 3.76336 | 3.69598 | 1.05161e-06 | PASS |
| cwt | wavelets/cwt + private scale reduction | 4533.27 | 12.5861 | 12.514 | 1.81284e-06 | PASS |
| feature_fusion | private weighted fusion + peak selection | 2.22053 | 0.737489 | 0.702844 | 9.83703e-05 | PASS |
| measurement_conversion | estimation measurement helper | 0.00108 | 0 | 0 | 0 | PASS |
| kalman | estimation/kalman_filter + private GPU pipeline | 0.185305 | 0.147953 | 0.078606 | 0 | PASS |
