# V5.2-02 算子接口审计

- status: `passed`
- operators: `81`
- passed: `81`
- failed: `0`

| 集合 | 算子 | API | 声明 | CPU | GPU | 测试 | Doxygen | 结论 |
| --- | --- | --- | ---: | ---: | ---: | --- | ---: | --- |
| A-task27 | `waveforms/chirp` | function `chirp` | 2 | 1 | 1 | `waveforms_test_chirp` | 2 | passed |
| A-task27 | `waveforms/gausspulse` | function `gausspulse` | 4 | 2 | 2 | `waveforms_test_gausspulse` | 4 | passed |
| B-core53 | `waveforms/sawtooth` | function `sawtooth` | 4 | 2 | 2 | `waveforms_test_sawtooth` | 4 | passed |
| B-core53 | `waveforms/square` | function `square` | 4 | 2 | 2 | `waveforms_test_square` | 4 | passed |
| A-task27 | `waveforms/unit_impulse` | function `unit_impulse` | 12 | 7 | 9 | `waveforms_test_unit_impulse` | 12 | passed |
| A-task27 | `bsplines/cubic` | function `cubic` | 2 | 1 | 1 | `bsplines_test_cubic` | 2 | passed |
| A-task27 | `bsplines/quadratic` | function `quadratic` | 2 | 1 | 1 | `bsplines_test_quadratic` | 2 | passed |
| B-core53 | `bsplines/gauss_spline` | function `gauss_spline` | 2 | 1 | 1 | `bsplines_test_gauss_spline` | 2 | passed |
| C-extended28 | `windows/get_window` | function `get_window` | 2 | 1 | 1 | `windows_test_get_window` | 2 | passed |
| C-extended28 | `windows/barthann` | function `barthann` | 2 | 2 | 2 | `windows_test_barthann` | 2 | passed |
| C-extended28 | `windows/bartlett` | function `bartlett` | 2 | 2 | 2 | `windows_test_bartlett` | 2 | passed |
| C-extended28 | `windows/blackman` | function `blackman` | 2 | 2 | 2 | `windows_test_blackman` | 2 | passed |
| C-extended28 | `windows/blackmanharris` | function `blackmanharris` | 2 | 2 | 2 | `windows_test_blackmanharris` | 2 | passed |
| C-extended28 | `windows/bohman` | function `bohman` | 2 | 2 | 2 | `windows_test_bohman` | 2 | passed |
| C-extended28 | `windows/boxcar` | function `boxcar` | 2 | 2 | 2 | `windows_test_boxcar` | 2 | passed |
| B-core53 | `windows/chebwin` | function `chebwin` | 2 | 2 | 2 | `windows_test_chebwin` | 2 | passed |
| C-extended28 | `windows/cosine` | function `cosine` | 2 | 2 | 2 | `windows_test_cosine` | 2 | passed |
| C-extended28 | `windows/exponential` | function `exponential` | 4 | 4 | 4 | `windows_test_exponential` | 4 | passed |
| C-extended28 | `windows/flattop` | function `flattop` | 2 | 2 | 2 | `windows_test_flattop` | 2 | passed |
| C-extended28 | `windows/gaussian` | function `gaussian` | 2 | 2 | 2 | `windows_test_gaussian` | 2 | passed |
| B-core53 | `windows/general_cosine` | function `general_cosine` | 2 | 1 | 5 | `windows_test_general_cosine` | 2 | passed |
| B-core53 | `windows/general_gaussian` | function `general_gaussian` | 2 | 2 | 2 | `windows_test_general_gaussian` | 2 | passed |
| C-extended28 | `windows/general_hamming` | function `general_hamming` | 2 | 4 | 4 | `windows_test_general_hamming` | 2 | passed |
| A-task27 | `windows/hamming` | function `hamming` | 2 | 2 | 2 | `windows_test_hamming` | 2 | passed |
| C-extended28 | `windows/hann` | function `hann` | 2 | 2 | 2 | `windows_test_hann` | 2 | passed |
| A-task27 | `windows/kaiser` | function `kaiser` | 2 | 3 | 3 | `windows_test_kaiser` | 2 | passed |
| C-extended28 | `windows/nuttall` | function `nuttall` | 2 | 2 | 2 | `windows_test_nuttall` | 2 | passed |
| B-core53 | `windows/parzen` | function `parzen` | 2 | 2 | 2 | `windows_test_parzen` | 2 | passed |
| B-core53 | `windows/taylor` | function `taylor` | 2 | 2 | 2 | `windows_test_taylor` | 2 | passed |
| B-core53 | `windows/triang` | function `triang` | 2 | 2 | 2 | `windows_test_triang` | 2 | passed |
| C-extended28 | `windows/tukey` | function `tukey` | 2 | 2 | 2 | `windows_test_tukey` | 2 | passed |
| C-extended28 | `filter_design/kaiser_beta` | function `kaiser_beta` | 2 | 2 | 3 | `filter_design_test_kaiser_beta` | 2 | passed |
| C-extended28 | `filter_design/kaiser_atten` | function `kaiser_atten` | 2 | 2 | 3 | `filter_design_test_kaiser_atten` | 2 | passed |
| C-extended28 | `filter_design/cmplx_sort` | function `cmplx_sort` | 4 | 2 | 4 | `filter_design_test_cmplx_sort` | 4 | passed |
| A-task27 | `filter_design/firwin` | function `firwin` | 4 | 3 | 3 | `filter_design_test_firwin` | 4 | passed |
| A-task27 | `filter_design/firwin2` | function `firwin2` | 2 | 1 | 1 | `filter_design_test_firwin2` | 2 | passed |
| B-core53 | `filtering/wiener` | function `wiener` | 6 | 5 | 5 | `filtering_test_wiener` | 6 | passed |
| A-task27 | `filtering/firfilter` | function `firfilter` | 4 | 3 | 2 | `filtering_test_firfilter` | 4 | passed |
| C-extended28 | `filtering/lfilter` | function `lfilter` | 4 | 2 | 2 | `filtering_test_lfilter` | 4 | passed |
| C-extended28 | `filtering/firfilter_zi` | function `firfilter_zi` | 2 | 2 | 1 | `filtering_test_firfilter_zi` | 2 | passed |
| B-core53 | `filtering/lfilter_zi` | function `lfilter_zi` | 2 | 2 | 1 | `filtering_test_lfilter_zi` | 2 | passed |
| B-core53 | `filtering/firfilter2` | function `firfilter2` | 2 | 1 | 2 | `filtering_test_firfilter2` | 2 | passed |
| C-extended28 | `filtering/filtfilt` | function `filtfilt` | 2 | 1 | 2 | `filtering_test_filtfilt` | 2 | passed |
| A-task27 | `filtering/sosfilt` | function `sosfilt` | 4 | 2 | 2 | `filtering_test_sosfilt` | 4 | passed |
| A-task27 | `filtering/hilbert` | function `hilbert` | 2 | 1 | 1 | `filtering_test_hilbert` | 2 | passed |
| A-task27 | `filtering/hilbert2` | function `hilbert2` | 2 | 1 | 1 | `filtering_test_hilbert2` | 2 | passed |
| B-core53 | `filtering/detrend` | function `detrend` | 2 | 1 | 1 | `filtering_test_detrend` | 2 | passed |
| B-core53 | `filtering/freq_shift` | function `freq_shift` | 2 | 1 | 1 | `filtering_test_freq_shift` | 2 | passed |
| B-core53 | `filtering/channelize_poly` | function `channelize_poly` | 2 | 1 | 1 | `filtering_test_channelize_poly` | 2 | passed |
| B-core53 | `filtering/decimate` | function `decimate` | 2 | 1 | 1 | `filtering_test_decimate` | 2 | passed |
| B-core53 | `filtering/resample` | function `resample` | 4 | 3 | 3 | `filtering_test_resample` | 4 | passed |
| B-core53 | `filtering/resample_poly` | function `resample_poly` | 2 | 1 | 1 | `filtering_test_resample_poly` | 2 | passed |
| B-core53 | `filtering/upfirdn` | function `upfirdn` | 2 | 3 | 1 | `filtering_test_upfirdn` | 2 | passed |
| A-task27 | `radartools/pulse_compression` | function `pulse_compression` | 2 | 1 | 1 | `radartools_test_pulse_compression` | 2 | passed |
| A-task27 | `radartools/pulse_doppler` | function `pulse_doppler` | 2 | 1 | 1 | `radartools_test_pulse_doppler` | 2 | passed |
| A-task27 | `radartools/ambgfun` | function `ambgfun` | 4 | 3 | 3 | `radartools_test_ambgfun` | 4 | passed |
| A-task27 | `radartools/cfar_alpha` | function `cfar_alpha` | 2 | 3 | 3 | `radartools_test_cfar_alpha` | 2 | passed |
| A-task27 | `radartools/ca_cfar` | function `ca_cfar` | 4 | 2 | 2 | `radartools_test_ca_cfar` | 4 | passed |
| C-extended28 | `radartools/mvdr` | function `mvdr` | 2 | 1 | 1 | `radartools_test_mvdr` | 2 | passed |
| B-core53 | `spectral/lombscargle` | function `lombscargle` | 2 | 1 | 1 | `spectral_test_lombscargle` | 2 | passed |
| C-extended28 | `spectral/periodogram` | function `periodogram` | 2 | 1 | 1 | `spectral_test_periodogram` | 2 | passed |
| C-extended28 | `spectral/welch` | function `welch` | 2 | 3 | 3 | `spectral_test_welch` | 2 | passed |
| B-core53 | `spectral/csd` | function `csd` | 2 | 2 | 2 | `spectral_test_csd` | 2 | passed |
| A-task27 | `spectral/spectrogram` | function `spectrogram` | 2 | 1 | 1 | `spectral_test_spectrogram` | 2 | passed |
| A-task27 | `spectral/stft` | function `stft` | 2 | 1 | 1 | `spectral_test_stft` | 2 | passed |
| B-core53 | `spectral/istft` | function `istft` | 2 | 1 | 1 | `spectral_test_istft` | 2 | passed |
| C-extended28 | `spectral/coherence` | function `coherence` | 2 | 1 | 1 | `spectral_test_coherence` | 2 | passed |
| B-core53 | `spectral/vectorstrength` | function `vectorstrength` | 4 | 3 | 2 | `spectral_test_vectorstrength` | 4 | passed |
| B-core53 | `wavelets/qmf` | function `qmf` | 2 | 1 | 1 | `wavelets_test_qmf` | 2 | passed |
| B-core53 | `wavelets/morlet` | function `morlet` | 2 | 1 | 1 | `wavelets_test_morlet` | 2 | passed |
| A-task27 | `wavelets/ricker` | function `ricker` | 2 | 1 | 1 | `wavelets_test_ricker` | 2 | passed |
| B-core53 | `wavelets/morlet2` | function `morlet2` | 2 | 1 | 1 | `wavelets_test_morlet2` | 2 | passed |
| A-task27 | `wavelets/cwt` | function `cwt` | 2 | 1 | 1 | `wavelets_test_cwt` | 2 | passed |
| A-task27 | `correlate/correlate` | function `correlate` | 4 | 2 | 2 | `correlate_test_correlate` | 4 | passed |
| A-task27 | `correlate/correlate2d` | function `correlate2d` | 4 | 2 | 2 | `correlate_test_correlate2d` | 4 | passed |
| C-extended28 | `correlate/correlation_lags` | function `correlation_lags` | 2 | 1 | 1 | `correlate_test_correlation_lags` | 2 | passed |
| A-task27 | `demod/fm_demod` | function `fm_demod` | 2 | 1 | 1 | `demod_test_fm_demod` | 2 | passed |
| A-task27 | `estimation/kalman_filter` | class `KalmanFilter` | 2 | 1 | 1 | `estimation_test_kalman_filter` | 2 | passed |
| A-task27 | `peak_finding/argrelextrema` | function `argrelextrema` | 2 | 3 | 3 | `peak_finding_test_argrelextrema` | 2 | passed |
| C-extended28 | `peak_finding/argrelmin` | function `argrelmin` | 2 | 1 | 1 | `peak_finding_test_argrelmin` | 2 | passed |
| C-extended28 | `peak_finding/argrelmax` | function `argrelmax` | 2 | 1 | 1 | `peak_finding_test_argrelmax` | 2 | passed |
