# All-Operator Benchmark Report

- run_id: `20260617_065810`
- scale_profile: `default`
- rows: `5`
- operators: `5`
- passed_rows: `5`
- status: passed=5
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| waveforms/chirp | 16384 | passed | 3.89e-06 | 4.7 | 9.66 |
| waveforms/gausspulse | 16384 | passed | 3.27e-07 | 6.02 | 11.3 |
| waveforms/sawtooth | 16384 | passed | 2.38e-07 | 2.27 | 4.67 |
| waveforms/square | 16384 | passed | 0 | 2.28 | 4.65 |
| waveforms/unit_impulse | 16384 | passed | 0 | 0.0568 | 0.234 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| waveforms/chirp | 3.89e-06 | 4.7 | 9.66 |
| waveforms/gausspulse | 3.27e-07 | 6.02 | 11.3 |
| waveforms/sawtooth | 2.38e-07 | 2.27 | 4.67 |
| waveforms/square | 0 | 2.28 | 4.65 |
| waveforms/unit_impulse | 0 | 0.0568 | 0.234 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| waveforms/unit_impulse | 0.0568 | 0.234 | 0 |
| waveforms/sawtooth | 2.27 | 4.67 | 2.38e-07 |
| waveforms/square | 2.28 | 4.65 | 0 |
| waveforms/chirp | 4.7 | 9.66 | 3.89e-06 |
| waveforms/gausspulse | 6.02 | 11.3 | 3.27e-07 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| waveforms/unit_impulse | 0.234 | 0.0568 | 0 |
| waveforms/square | 4.65 | 2.28 | 0 |
| waveforms/sawtooth | 4.67 | 2.27 | 2.38e-07 |
| waveforms/chirp | 9.66 | 4.7 | 3.89e-06 |
| waveforms/gausspulse | 11.3 | 6.02 | 3.27e-07 |
