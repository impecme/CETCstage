# V5.5 Gate Summary

- status: `passed`
- all81 rows: `81`
- all81 operators: `81`
- all81 failed: `0`
- module regression: `passed`
- task smoke: `passed`
- contracts: `passed`
- compact plot figures: `12` modules, `81` operators

## Top GPU E2E

| operator | gpu_e2e_ms | kernel_ms | speedup | mixed_error |
| --- | ---: | ---: | ---: | ---: |
| radartools/ambgfun | 167.792 | 167.26400000000001 | 50.622999999999998 | 0 |
| spectral/lombscargle | 12.5 | 12.292899999999999 | 172.119 | 9.6234599999999992e-06 |
| radartools/mvdr | 11.148199999999999 | 0.840534 | 1.9104300000000001 | 0 |
| filtering/hilbert2 | 3.6902599999999999 | 3.6245500000000002 | 32.3782 | 1.7134900000000001e-05 |
| filtering/wiener | 3.52101 | 3.3814299999999999 | 194.23699999999999 | 9.7552699999999992e-07 |
| wavelets/cwt | 3.50353 | 3.37968 | 215.17400000000001 | 0 |
| radartools/ca_cfar | 2.1069800000000001 | 1.8602000000000001 | 4.0521200000000004 | 0 |
| spectral/welch | 2.0256500000000002 | 1.6479699999999999 | 1.35347 | 3.1610300000000001e-07 |
| wavelets/morlet2 | 1.98108 | 1.87849 | 31.7759 | 0 |
| wavelets/ricker | 1.8063199999999999 | 1.75545 | 12.109299999999999 | 0 |

## Module Regression

| module | source | status | operators | failed |
| --- | --- | --- | ---: | --- |
| waveforms | aggregate | passed | 5/5 | - |
| bsplines | aggregate | passed | 3/3 | - |
| windows | aggregate | passed | 23/23 | - |
| filter_design | aggregate | passed | 5/5 | - |
| filtering | aggregate | passed | 17/17 | - |
| radartools | aggregate | passed | 6/6 | - |
| spectral | aggregate | passed | 9/9 | - |
| wavelets | aggregate | passed | 5/5 | - |
| correlate | operator_dirs | passed | 3/3 | - |
| demod | operator_dirs | passed | 1/1 | - |
| estimation | operator_dirs | passed | 1/1 | - |
| peak_finding | operator_dirs | passed | 3/3 | - |
