# task2_features Step Metrics

| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| filter | filter_design/firwin + filtering/firfilter public complex64 path | 22.3546 | 1.4971 | 1.47727 | 3.35682e-06 | PASS |
| demod | demod/fm_demod + private batched score | 7.32193 | 0.203421 | 0.170366 | 0.000245506 | PASS |
| correlate | correlate/correlate + private normalization | 4741.63 | 1.35246 | 1.28127 | 7.83549e-06 | PASS |
| spectrogram | spectral/spectrogram + private band score | 30.4096 | 2.12958 | 2.0669 | 1.06843e-06 | PASS |
| cwt | wavelets/cwt + private scale reduction | 2286.17 | 6.29462 | 6.21984 | 1.29036e-06 | PASS |
| feature_fusion | private weighted fusion + peak selection | 1.09185 | 0.400981 | 0.374468 | 9.83703e-05 | PASS |
| measurement_conversion | estimation measurement helper | 0.00012 | 0 | 0 | 0 | PASS |
| kalman | estimation/kalman_filter + private GPU pipeline | 0.10732 | 0.096761 | 0.063938 | 0 | PASS |
