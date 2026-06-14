#pragma once

#include "cusignal/core/types.hpp"

namespace cusignal_demo::task2_features
{
    cusignal::core::CudaRealArray extract_real_part_cuda(const cusignal::core::CudaComplexArray &input);
    cusignal::core::CudaRealArray extract_imag_part_cuda(const cusignal::core::CudaComplexArray &input);
    cusignal::core::CudaComplexArray combine_complex_cuda(
        const cusignal::core::CudaRealArray &real_part,
        const cusignal::core::CudaRealArray &imag_part);

    cusignal::core::CudaComplexArray extract_row_complex_cuda(
        const cusignal::core::CudaComplexArray &input,
        int row_index);
    cusignal::core::CudaRealArray extract_row_real_cuda(
        const cusignal::core::CudaRealArray &input,
        int row_index);
    cusignal::core::CudaRealSignal extract_row_real_signal_cuda(
        const cusignal::core::CudaRealArray &input,
        int row_index);
    void store_row_real_cuda(
        const cusignal::core::CudaRealArray &row,
        cusignal::core::CudaRealArray &output,
        int row_index);

    cusignal::core::CudaRealArray complex_abs_cuda(const cusignal::core::CudaComplexArray &input);
    cusignal::core::CudaRealArray pad_last_value_cuda(
        const cusignal::core::CudaRealArray &input,
        std::size_t target_len);
    cusignal::core::CudaRealArray normalize_nonnegative_cuda(const cusignal::core::CudaRealArray &input);
    cusignal::core::CudaRealArray batched_demod_score_cuda(const cusignal::core::CudaComplexArray &input);
    cusignal::core::CudaRealArray spectrogram_band_score_cuda(
        const cusignal::core::CudaRealArray &values,
        const cusignal::core::CudaRealSignal &freqs,
        const cusignal::core::CudaRealSignal &times,
        int sample_count,
        float band_low,
        float band_high,
        float fs);
    cusignal::core::CudaRealArray cwt_max_score_cuda(const cusignal::core::CudaComplexArray &values);
    cusignal::core::CudaRealArray weighted_sum_cuda(
        const cusignal::core::CudaRealArray &corr_score,
        const cusignal::core::CudaRealArray &demod_score,
        const cusignal::core::CudaRealArray &wavelet_score,
        const cusignal::core::CudaRealArray &spectrogram_score,
        float corr_weight,
        float demod_weight,
        float wavelet_weight,
        float spectrogram_weight);
    cusignal::core::CudaRealArray smooth_with_weights_cuda(
        const cusignal::core::CudaRealArray &input,
        const cusignal::core::CudaRealSignal &weights);
    void fuse_feature_scores_cuda(
        const cusignal::core::CudaRealArray &corr_score,
        const cusignal::core::CudaRealArray &demod_score,
        const cusignal::core::CudaRealArray &wavelet_score,
        const cusignal::core::CudaRealArray &spectrogram_score,
        const cusignal::core::CudaRealSignal &weights,
        int peak_order,
        cusignal::core::CudaRealArray &feature_scores,
        cusignal::core::CudaRealSignal &peak_track);
    cusignal::core::CudaRealSignal kalman_track_from_peaks_cuda(
        const cusignal::core::CudaRealSignal &peak_track);

    cusignal::core::CudaIndexSignal argmax_all_cuda(const cusignal::core::CudaRealArray &score);
    cusignal::core::CudaIndexSignal argmax_from_candidates_cuda(
        const cusignal::core::CudaRealArray &score,
        const cusignal::core::CudaIndexSignal &candidates);
    cusignal::core::CudaRealArray index_to_measurement_cuda(const cusignal::core::CudaIndexSignal &index);
    void initialize_state_from_index_cuda(
        const cusignal::core::CudaIndexSignal &index,
        cusignal::core::CudaRealArray &state);
    void write_index_to_track_cuda(
        const cusignal::core::CudaIndexSignal &index,
        cusignal::core::CudaRealSignal &track,
        int frame_index);
    void write_state_position_to_track_cuda(
        const cusignal::core::CudaRealArray &state,
        cusignal::core::CudaRealSignal &track,
        int frame_index);
}
