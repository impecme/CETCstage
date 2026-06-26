#pragma once

#include "cusignal/core/types.hpp"

namespace cusignal_demo::task2_features
{
    cusignal::core::ZxGpuRealArray extract_real_part_zx_gpu(const cusignal::core::ZxGpuComplexArray &input);
    cusignal::core::ZxGpuRealArray extract_imag_part_zx_gpu(const cusignal::core::ZxGpuComplexArray &input);
    cusignal::core::ZxGpuComplexArray combine_complex_zx_gpu(
        const cusignal::core::ZxGpuRealArray &real_part,
        const cusignal::core::ZxGpuRealArray &imag_part);
    cusignal::core::ZxGpuComplexArray complex_firfilter_zx_gpu(
        const cusignal::core::ZxGpuComplexArray &input,
        const cusignal::core::ZxGpuRealSignal &taps,
        cusignal::core::ZxGpuRealArray &real_output);

    cusignal::core::ZxGpuComplexArray extract_row_complex_zx_gpu(
        const cusignal::core::ZxGpuComplexArray &input,
        int row_index);
    cusignal::core::ZxGpuRealArray extract_row_real_zx_gpu(
        const cusignal::core::ZxGpuRealArray &input,
        int row_index);
    cusignal::core::ZxGpuRealSignal extract_row_real_signal_zx_gpu(
        const cusignal::core::ZxGpuRealArray &input,
        int row_index);
    void store_row_real_zx_gpu(
        const cusignal::core::ZxGpuRealArray &row,
        cusignal::core::ZxGpuRealArray &output,
        int row_index);

    cusignal::core::ZxGpuRealArray complex_abs_zx_gpu(const cusignal::core::ZxGpuComplexArray &input);
    cusignal::core::ZxGpuRealArray pad_last_value_zx_gpu(
        const cusignal::core::ZxGpuRealArray &input,
        std::size_t target_len);
    cusignal::core::ZxGpuRealArray normalize_nonnegative_zx_gpu(const cusignal::core::ZxGpuRealArray &input);
    cusignal::core::ZxGpuRealArray normalize_rows_nonnegative_zx_gpu(const cusignal::core::ZxGpuRealArray &input);
    cusignal::core::ZxGpuRealArray batched_demod_score_zx_gpu(const cusignal::core::ZxGpuComplexArray &input);
    cusignal::core::ZxGpuRealArray batched_correlate_score_zx_gpu(
        const cusignal::core::ZxGpuComplexArray &frames,
        const cusignal::core::ZxGpuComplexArray &templ);
    cusignal::core::ZxGpuRealArray extract_frame_real_3d_zx_gpu(
        const cusignal::core::ZxGpuRealArray &input,
        int frame_index);
    cusignal::core::ZxGpuRealArray spectrogram_band_score_zx_gpu(
        const cusignal::core::ZxGpuRealArray &values,
        const cusignal::core::ZxGpuRealSignal &freqs,
        const cusignal::core::ZxGpuRealSignal &times,
        int sample_count,
        float band_low,
        float band_high,
        float fs);
    cusignal::core::ZxGpuRealArray batched_spectrogram_band_score_zx_gpu(
        const cusignal::core::ZxGpuRealArray &values,
        const cusignal::core::ZxGpuRealSignal &freqs,
        const cusignal::core::ZxGpuRealSignal &times,
        int sample_count,
        float band_low,
        float band_high,
        float fs);
    cusignal::core::ZxGpuRealArray direct_spectrogram_band_score_zx_gpu(
        const cusignal::core::ZxGpuRealArray &frames,
        const cusignal::core::ZxGpuRealSignal &window,
        int nperseg,
        int noverlap,
        int nfft,
        float band_low,
        float band_high,
        float fs);
    cusignal::core::ZxGpuRealArray batched_cwt_max_score_zx_gpu(
        const cusignal::core::ZxGpuRealArray &frames,
        const cusignal::core::RealSignal &widths);
    cusignal::core::ZxGpuRealArray cwt_max_score_zx_gpu(const cusignal::core::ZxGpuComplexArray &values);
    cusignal::core::ZxGpuRealArray weighted_sum_zx_gpu(
        const cusignal::core::ZxGpuRealArray &corr_score,
        const cusignal::core::ZxGpuRealArray &demod_score,
        const cusignal::core::ZxGpuRealArray &wavelet_score,
        const cusignal::core::ZxGpuRealArray &spectrogram_score,
        float corr_weight,
        float demod_weight,
        float wavelet_weight,
        float spectrogram_weight);
    cusignal::core::ZxGpuRealArray smooth_with_weights_zx_gpu(
        const cusignal::core::ZxGpuRealArray &input,
        const cusignal::core::ZxGpuRealSignal &weights);
    void fuse_feature_scores_zx_gpu(
        const cusignal::core::ZxGpuRealArray &corr_score,
        const cusignal::core::ZxGpuRealArray &demod_score,
        const cusignal::core::ZxGpuRealArray &wavelet_score,
        const cusignal::core::ZxGpuRealArray &spectrogram_score,
        const cusignal::core::ZxGpuRealSignal &weights,
        int peak_order,
        cusignal::core::ZxGpuRealArray &feature_scores,
        cusignal::core::ZxGpuRealSignal &peak_track);
    cusignal::core::ZxGpuRealSignal kalman_track_from_peaks_zx_gpu(
        const cusignal::core::ZxGpuRealSignal &peak_track);

    cusignal::core::ZxGpuIndexSignal argmax_all_zx_gpu(const cusignal::core::ZxGpuRealArray &score);
    cusignal::core::ZxGpuIndexSignal argmax_from_candidates_zx_gpu(
        const cusignal::core::ZxGpuRealArray &score,
        const cusignal::core::ZxGpuIndexSignal &candidates);
    cusignal::core::ZxGpuRealArray index_to_measurement_zx_gpu(const cusignal::core::ZxGpuIndexSignal &index);
    void initialize_state_from_index_zx_gpu(
        const cusignal::core::ZxGpuIndexSignal &index,
        cusignal::core::ZxGpuRealArray &state);
    void write_index_to_track_zx_gpu(
        const cusignal::core::ZxGpuIndexSignal &index,
        cusignal::core::ZxGpuRealSignal &track,
        int frame_index);
    void write_state_position_to_track_zx_gpu(
        const cusignal::core::ZxGpuRealArray &state,
        cusignal::core::ZxGpuRealSignal &track,
        int frame_index);
}
