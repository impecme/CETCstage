#include "cusignal/estimation/estimation.hpp"

#include <cuda_runtime.h>

#include <stdexcept>
#include <string>
#include <vector>

#include "cusignal/core/helpers.hpp"

#include "../common/estimation_detail.hpp"

namespace
{
    using cusignal::core::ZxGpuRealArray;
    using cusignal::core::Shape;
    namespace detail = cusignal::estimation_detail;

    constexpr int kThreadsPerBlock = 64;
    thread_local float g_last_kernel_ms = 0.0f;

    void throw_on_zx_gpu_error(cudaError_t status, const char *what)
    {
        if (status != cudaSuccess)
        {
            throw std::runtime_error(std::string(what) + ": " + cudaGetErrorString(status));
        }
    }

    void check_kernel_launch(const char *what)
    {
        throw_on_zx_gpu_error(cudaGetLastError(), what);
    }

    class ScopedZxGpuEvents
    {
    public:
        ScopedZxGpuEvents()
        {
            throw_on_zx_gpu_error(cudaEventCreate(&start_), "cudaEventCreate(start)");
            throw_on_zx_gpu_error(cudaEventCreate(&stop_), "cudaEventCreate(stop)");
        }

        ~ScopedZxGpuEvents()
        {
            if (start_ != nullptr)
            {
                cudaEventDestroy(start_);
            }
            if (stop_ != nullptr)
            {
                cudaEventDestroy(stop_);
            }
        }

        template <typename Callable>
        float measure(Callable callable)
        {
            throw_on_zx_gpu_error(cudaEventRecord(start_), "cudaEventRecord(start)");
            callable();
            throw_on_zx_gpu_error(cudaEventRecord(stop_), "cudaEventRecord(stop)");
            throw_on_zx_gpu_error(cudaEventSynchronize(stop_), "cudaEventSynchronize(stop)");
            float elapsed_ms = 0.0f;
            throw_on_zx_gpu_error(cudaEventElapsedTime(&elapsed_ms, start_, stop_), "cudaEventElapsedTime");
            return elapsed_ms;
        }

    private:
        cudaEvent_t start_ = nullptr;
        cudaEvent_t stop_ = nullptr;
    };

    struct EstimationWorkspace
    {
        ZxGpuRealArray control_storage;
        ZxGpuRealArray measurement_storage;
        ZxGpuRealArray scratch_a;
        ZxGpuRealArray scratch_b;
        ZxGpuRealArray scratch_c;
        ZxGpuRealArray scratch_d;
        ZxGpuRealArray scratch_e;
        ZxGpuRealArray scratch_f;
        ZxGpuRealArray scratch_g;
        ZxGpuRealArray scratch_h;
        ZxGpuRealArray scratch_i;
    };

    thread_local EstimationWorkspace g_workspace;

    inline int block_count(int count)
    {
        return count == 0 ? 0 : (count + kThreadsPerBlock - 1) / kThreadsPerBlock;
    }

    void copy_device_array(const ZxGpuRealArray &src, ZxGpuRealArray &dst)
    {
        dst.resize(src.shape(), false);
        if (src.size() == 0)
        {
            return;
        }
        throw_on_zx_gpu_error(
            cudaMemcpy(
                dst.data(),
                src.data(),
                src.size() * sizeof(float),
                cudaMemcpyDeviceToDevice),
            "cudaMemcpy D2D");
    }

    void validate_device_shape(const Shape &actual, const Shape &expected, const char *name)
    {
        if (actual != expected)
        {
            throw std::invalid_argument(std::string(name) + " has invalid shape");
        }
    }

    void validate_filter_state(
        const cusignal::zx_gpu_backend::estimation::KalmanFilter &filter)
    {
        validate_device_shape(
            filter.x.shape(),
            detail::state_vector_shape(filter.points(), filter.dim_x()),
            "x");
        validate_device_shape(
            filter.P.shape(),
            detail::square_matrix_shape(filter.points(), filter.dim_x()),
            "P");
        validate_device_shape(
            filter.z.shape(),
            detail::state_vector_shape(filter.points(), filter.dim_z()),
            "z");
        validate_device_shape(
            filter.R.shape(),
            detail::square_matrix_shape(filter.points(), filter.dim_z()),
            "R");
        validate_device_shape(
            filter.Q.shape(),
            detail::square_matrix_shape(filter.points(), filter.dim_x()),
            "Q");
        validate_device_shape(
            filter.F.shape(),
            detail::square_matrix_shape(filter.points(), filter.dim_x()),
            "F");
        validate_device_shape(
            filter.H.shape(),
            detail::rectangular_matrix_shape(filter.points(), filter.dim_z(), filter.dim_x()),
            "H");
        validate_device_shape(
            filter.B.shape(),
            detail::rectangular_matrix_shape(filter.points(), filter.dim_x(), filter.dim_u()),
            "B");
        validate_device_shape(
            filter.u.shape(),
            detail::state_vector_shape(filter.points(), filter.dim_u()),
            "u");
        validate_device_shape(
            filter.alpha_sq.shape(),
            detail::state_vector_shape(filter.points(), 1),
            "alpha_sq");
    }

    __global__ void predict_kernel(
        float *x,
        float *P,
        const float *F,
        const float *Q,
        const float *B,
        const float *u,
        const float *alpha_sq,
        int points,
        int dim_x,
        int dim_u,
        float *x_new,
        float *fp,
        float *p_new)
    {
        const int point = blockIdx.x * blockDim.x + threadIdx.x;
        if (point >= points)
        {
            return;
        }

        const std::size_t x_off = static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_x);
        const std::size_t p_off = static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_x * dim_x);
        const std::size_t u_off = static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_u);
        const float alpha = alpha_sq[point];

        float *x_tmp = x_new + x_off;
        float *fp_tmp = fp + p_off;
        float *p_tmp = p_new + p_off;

        for (int row = 0; row < dim_x; ++row)
        {
            float value = 0.0f;
            for (int col = 0; col < dim_x; ++col)
            {
                value += F[p_off + static_cast<std::size_t>(row * dim_x + col)] *
                         x[x_off + static_cast<std::size_t>(col)];
            }
            if (dim_u > 0)
            {
                for (int col = 0; col < dim_u; ++col)
                {
                    value += B[static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_x * dim_u) +
                               static_cast<std::size_t>(row * dim_u + col)] *
                             u[u_off + static_cast<std::size_t>(col)];
                }
            }
            x_tmp[static_cast<std::size_t>(row)] = value;
        }

        for (int row = 0; row < dim_x; ++row)
        {
            for (int col = 0; col < dim_x; ++col)
            {
                float value = 0.0f;
                for (int inner = 0; inner < dim_x; ++inner)
                {
                    value += F[p_off + static_cast<std::size_t>(row * dim_x + inner)] *
                             P[p_off + static_cast<std::size_t>(inner * dim_x + col)];
                }
                fp_tmp[static_cast<std::size_t>(row * dim_x + col)] = value;
            }
        }

        for (int row = 0; row < dim_x; ++row)
        {
            for (int col = 0; col < dim_x; ++col)
            {
                float value = 0.0f;
                for (int inner = 0; inner < dim_x; ++inner)
                {
                    value += fp_tmp[static_cast<std::size_t>(row * dim_x + inner)] *
                             F[p_off + static_cast<std::size_t>(col * dim_x + inner)];
                }
                p_tmp[static_cast<std::size_t>(row * dim_x + col)] =
                    alpha * value + Q[p_off + static_cast<std::size_t>(row * dim_x + col)];
            }
        }

        for (int row = 0; row < dim_x; ++row)
        {
            x[x_off + static_cast<std::size_t>(row)] = x_tmp[static_cast<std::size_t>(row)];
        }
        for (int index = 0; index < dim_x * dim_x; ++index)
        {
            P[p_off + static_cast<std::size_t>(index)] = p_tmp[static_cast<std::size_t>(index)];
        }
    }

    __global__ void predict_small_kernel(
        float *x,
        float *P,
        const float *F,
        const float *Q,
        const float *B,
        float *u,
        const float *control,
        bool use_control,
        const float *alpha_sq,
        int points,
        int dim_x,
        int dim_u)
    {
        const int point = blockIdx.x * blockDim.x + threadIdx.x;
        if (point >= points || dim_x > 4 || dim_u > 2)
        {
            return;
        }

        const std::size_t x_off = static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_x);
        const std::size_t p_off = static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_x * dim_x);
        const std::size_t u_off = static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_u);
        const std::size_t b_off = static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_x * dim_u);

        float x_old[4] = {0.0f, 0.0f, 0.0f, 0.0f};
        float u_local[2] = {0.0f, 0.0f};
        float x_new[4] = {0.0f, 0.0f, 0.0f, 0.0f};
        float fp[16];
        float p_new[16];

        for (int row = 0; row < dim_x; ++row)
        {
            x_old[row] = x[x_off + static_cast<std::size_t>(row)];
        }
        for (int col = 0; col < dim_u; ++col)
        {
            const float value = use_control ? control[u_off + static_cast<std::size_t>(col)]
                                            : u[u_off + static_cast<std::size_t>(col)];
            u_local[col] = value;
            if (use_control)
            {
                u[u_off + static_cast<std::size_t>(col)] = value;
            }
        }

        for (int row = 0; row < dim_x; ++row)
        {
            float value = 0.0f;
            for (int col = 0; col < dim_x; ++col)
            {
                value += F[p_off + static_cast<std::size_t>(row * dim_x + col)] * x_old[col];
            }
            for (int col = 0; col < dim_u; ++col)
            {
                value += B[b_off + static_cast<std::size_t>(row * dim_u + col)] * u_local[col];
            }
            x_new[row] = value;
        }

        for (int row = 0; row < dim_x; ++row)
        {
            for (int col = 0; col < dim_x; ++col)
            {
                float value = 0.0f;
                for (int inner = 0; inner < dim_x; ++inner)
                {
                    value += F[p_off + static_cast<std::size_t>(row * dim_x + inner)] *
                             P[p_off + static_cast<std::size_t>(inner * dim_x + col)];
                }
                fp[row * 4 + col] = value;
            }
        }

        const float alpha = alpha_sq[point];
        for (int row = 0; row < dim_x; ++row)
        {
            for (int col = 0; col < dim_x; ++col)
            {
                float value = 0.0f;
                for (int inner = 0; inner < dim_x; ++inner)
                {
                    value += fp[row * 4 + inner] *
                             F[p_off + static_cast<std::size_t>(col * dim_x + inner)];
                }
                p_new[row * 4 + col] =
                    alpha * value + Q[p_off + static_cast<std::size_t>(row * dim_x + col)];
            }
        }

        for (int row = 0; row < dim_x; ++row)
        {
            x[x_off + static_cast<std::size_t>(row)] = x_new[row];
        }
        for (int row = 0; row < dim_x; ++row)
        {
            for (int col = 0; col < dim_x; ++col)
            {
                P[p_off + static_cast<std::size_t>(row * dim_x + col)] = p_new[row * 4 + col];
            }
        }
    }

    template <int DimX, int DimU>
    __global__ void predict_fixed_kernel(
        float *x,
        float *P,
        const float *F,
        const float *Q,
        const float *B,
        float *u,
        const float *control,
        bool use_control,
        const float *alpha_sq,
        int points)
    {
        const int point = blockIdx.x * blockDim.x + threadIdx.x;
        if (point >= points)
        {
            return;
        }

        const std::size_t x_off = static_cast<std::size_t>(point) * DimX;
        const std::size_t p_off = static_cast<std::size_t>(point) * DimX * DimX;
        const std::size_t u_off = static_cast<std::size_t>(point) * DimU;
        const std::size_t b_off = static_cast<std::size_t>(point) * DimX * DimU;

        float x_old[DimX];
        float u_local[DimU];
        float x_new[DimX];
        float fp[DimX * DimX];
        float p_new[DimX * DimX];

#pragma unroll
        for (int row = 0; row < DimX; ++row)
        {
            x_old[row] = x[x_off + static_cast<std::size_t>(row)];
        }
#pragma unroll
        for (int col = 0; col < DimU; ++col)
        {
            const float value = use_control ? control[u_off + static_cast<std::size_t>(col)]
                                            : u[u_off + static_cast<std::size_t>(col)];
            u_local[col] = value;
            if (use_control)
            {
                u[u_off + static_cast<std::size_t>(col)] = value;
            }
        }

#pragma unroll
        for (int row = 0; row < DimX; ++row)
        {
            float value = 0.0f;
#pragma unroll
            for (int col = 0; col < DimX; ++col)
            {
                value += F[p_off + static_cast<std::size_t>(row * DimX + col)] * x_old[col];
            }
#pragma unroll
            for (int col = 0; col < DimU; ++col)
            {
                value += B[b_off + static_cast<std::size_t>(row * DimU + col)] * u_local[col];
            }
            x_new[row] = value;
        }

#pragma unroll
        for (int row = 0; row < DimX; ++row)
        {
#pragma unroll
            for (int col = 0; col < DimX; ++col)
            {
                float value = 0.0f;
#pragma unroll
                for (int inner = 0; inner < DimX; ++inner)
                {
                    value += F[p_off + static_cast<std::size_t>(row * DimX + inner)] *
                             P[p_off + static_cast<std::size_t>(inner * DimX + col)];
                }
                fp[row * DimX + col] = value;
            }
        }

        const float alpha = alpha_sq[point];
#pragma unroll
        for (int row = 0; row < DimX; ++row)
        {
#pragma unroll
            for (int col = 0; col < DimX; ++col)
            {
                float value = 0.0f;
#pragma unroll
                for (int inner = 0; inner < DimX; ++inner)
                {
                    value += fp[row * DimX + inner] *
                             F[p_off + static_cast<std::size_t>(col * DimX + inner)];
                }
                p_new[row * DimX + col] =
                    alpha * value + Q[p_off + static_cast<std::size_t>(row * DimX + col)];
            }
        }

#pragma unroll
        for (int row = 0; row < DimX; ++row)
        {
            x[x_off + static_cast<std::size_t>(row)] = x_new[row];
        }
#pragma unroll
        for (int index = 0; index < DimX * DimX; ++index)
        {
            P[p_off + static_cast<std::size_t>(index)] = p_new[index];
        }
    }

    __device__ bool invert_matrix_device(float *matrix, float *inverse, int n)
    {
        for (int row = 0; row < n; ++row)
        {
            for (int col = 0; col < n; ++col)
            {
                inverse[static_cast<std::size_t>(row * n + col)] = (row == col) ? 1.0f : 0.0f;
            }
        }

        for (int pivot = 0; pivot < n; ++pivot)
        {
            int pivot_row = pivot;
            float max_abs = fabsf(matrix[static_cast<std::size_t>(pivot * n + pivot)]);
            for (int row = pivot + 1; row < n; ++row)
            {
                const float candidate =
                    fabsf(matrix[static_cast<std::size_t>(row * n + pivot)]);
                if (candidate > max_abs)
                {
                    max_abs = candidate;
                    pivot_row = row;
                }
            }
            if (!(max_abs > 0.0f))
            {
                return false;
            }
            if (pivot_row != pivot)
            {
                for (int col = 0; col < n; ++col)
                {
                    const std::size_t a = static_cast<std::size_t>(pivot * n + col);
                    const std::size_t b = static_cast<std::size_t>(pivot_row * n + col);
                    const float tmp_matrix = matrix[a];
                    matrix[a] = matrix[b];
                    matrix[b] = tmp_matrix;
                    const float tmp_inverse = inverse[a];
                    inverse[a] = inverse[b];
                    inverse[b] = tmp_inverse;
                }
            }

            const float diag = matrix[static_cast<std::size_t>(pivot * n + pivot)];
            for (int col = 0; col < n; ++col)
            {
                matrix[static_cast<std::size_t>(pivot * n + col)] /= diag;
                inverse[static_cast<std::size_t>(pivot * n + col)] /= diag;
            }
            for (int row = 0; row < n; ++row)
            {
                if (row == pivot)
                {
                    continue;
                }
                const float factor = matrix[static_cast<std::size_t>(row * n + pivot)];
                if (factor == 0.0f)
                {
                    continue;
                }
                for (int col = 0; col < n; ++col)
                {
                    matrix[static_cast<std::size_t>(row * n + col)] -=
                        factor * matrix[static_cast<std::size_t>(pivot * n + col)];
                    inverse[static_cast<std::size_t>(row * n + col)] -=
                        factor * inverse[static_cast<std::size_t>(pivot * n + col)];
                }
            }
        }
        return true;
    }

    __global__ void update_kernel(
        float *x,
        float *P,
        const float *z,
        const float *H,
        const float *R,
        int points,
        int dim_x,
        int dim_z,
        float *innovation,
        float *hp,
        float *s,
        float *s_inv,
        float *pht,
        float *k,
        float *kh,
        float *x_new,
        float *p_new)
    {
        const int point = blockIdx.x * blockDim.x + threadIdx.x;
        if (point >= points)
        {
            return;
        }

        const std::size_t x_off = static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_x);
        const std::size_t z_off = static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_z);
        const std::size_t p_off = static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_x * dim_x);
        const std::size_t h_off = static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_z * dim_x);
        const std::size_t r_off = static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_z * dim_z);
        const std::size_t zx_off = static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_z * dim_x);
        const std::size_t zz_off = static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_z * dim_z);

        float *innov_tmp = innovation + z_off;
        float *hp_tmp = hp + zx_off;
        float *s_tmp = s + zz_off;
        float *sinv_tmp = s_inv + zz_off;
        float *pht_tmp = pht + static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_x * dim_z);
        float *k_tmp = k + static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_x * dim_z);
        float *kh_tmp = kh + p_off;
        float *x_tmp = x_new + x_off;
        float *p_tmp = p_new + p_off;

        for (int row = 0; row < dim_z; ++row)
        {
            float hx = 0.0f;
            for (int col = 0; col < dim_x; ++col)
            {
                hx += H[h_off + static_cast<std::size_t>(row * dim_x + col)] *
                      x[x_off + static_cast<std::size_t>(col)];
            }
            innov_tmp[static_cast<std::size_t>(row)] =
                z[z_off + static_cast<std::size_t>(row)] - hx;
        }

        for (int row = 0; row < dim_z; ++row)
        {
            for (int col = 0; col < dim_x; ++col)
            {
                float value = 0.0f;
                for (int inner = 0; inner < dim_x; ++inner)
                {
                    value += H[h_off + static_cast<std::size_t>(row * dim_x + inner)] *
                             P[p_off + static_cast<std::size_t>(inner * dim_x + col)];
                }
                hp_tmp[static_cast<std::size_t>(row * dim_x + col)] = value;
            }
        }

        for (int row = 0; row < dim_z; ++row)
        {
            for (int col = 0; col < dim_z; ++col)
            {
                float value = 0.0f;
                for (int inner = 0; inner < dim_x; ++inner)
                {
                    value += hp_tmp[static_cast<std::size_t>(row * dim_x + inner)] *
                             H[h_off + static_cast<std::size_t>(col * dim_x + inner)];
                }
                s_tmp[static_cast<std::size_t>(row * dim_z + col)] =
                    value + R[r_off + static_cast<std::size_t>(row * dim_z + col)];
            }
        }

        for (int index = 0; index < dim_z * dim_z; ++index)
        {
            sinv_tmp[static_cast<std::size_t>(index)] = s_tmp[static_cast<std::size_t>(index)];
        }
        if (!invert_matrix_device(sinv_tmp, s_tmp, dim_z))
        {
            return;
        }
        for (int index = 0; index < dim_z * dim_z; ++index)
        {
            sinv_tmp[static_cast<std::size_t>(index)] = s_tmp[static_cast<std::size_t>(index)];
        }

        for (int row = 0; row < dim_x; ++row)
        {
            for (int col = 0; col < dim_z; ++col)
            {
                float value = 0.0f;
                for (int inner = 0; inner < dim_x; ++inner)
                {
                    value += P[p_off + static_cast<std::size_t>(row * dim_x + inner)] *
                             H[h_off + static_cast<std::size_t>(col * dim_x + inner)];
                }
                pht_tmp[static_cast<std::size_t>(row * dim_z + col)] = value;
            }
        }

        for (int row = 0; row < dim_x; ++row)
        {
            for (int col = 0; col < dim_z; ++col)
            {
                float value = 0.0f;
                for (int inner = 0; inner < dim_z; ++inner)
                {
                    value += pht_tmp[static_cast<std::size_t>(row * dim_z + inner)] *
                             sinv_tmp[static_cast<std::size_t>(inner * dim_z + col)];
                }
                k_tmp[static_cast<std::size_t>(row * dim_z + col)] = value;
            }
        }

        for (int row = 0; row < dim_x; ++row)
        {
            float value = x[x_off + static_cast<std::size_t>(row)];
            for (int inner = 0; inner < dim_z; ++inner)
            {
                value += k_tmp[static_cast<std::size_t>(row * dim_z + inner)] *
                         innov_tmp[static_cast<std::size_t>(inner)];
            }
            x_tmp[static_cast<std::size_t>(row)] = value;
        }

        for (int row = 0; row < dim_x; ++row)
        {
            for (int col = 0; col < dim_x; ++col)
            {
                float value = (row == col) ? 1.0f : 0.0f;
                for (int inner = 0; inner < dim_z; ++inner)
                {
                    value -= k_tmp[static_cast<std::size_t>(row * dim_z + inner)] *
                             H[h_off + static_cast<std::size_t>(inner * dim_x + col)];
                }
                kh_tmp[static_cast<std::size_t>(row * dim_x + col)] = value;
            }
        }

        for (int row = 0; row < dim_x; ++row)
        {
            for (int col = 0; col < dim_x; ++col)
            {
                float value = 0.0f;
                for (int inner = 0; inner < dim_x; ++inner)
                {
                    value += kh_tmp[static_cast<std::size_t>(row * dim_x + inner)] *
                             P[p_off + static_cast<std::size_t>(inner * dim_x + col)];
                }
                p_tmp[static_cast<std::size_t>(row * dim_x + col)] = value;
            }
        }

        for (int row = 0; row < dim_x; ++row)
        {
            x[x_off + static_cast<std::size_t>(row)] = x_tmp[static_cast<std::size_t>(row)];
        }
        for (int index = 0; index < dim_x * dim_x; ++index)
        {
            P[p_off + static_cast<std::size_t>(index)] = p_tmp[static_cast<std::size_t>(index)];
        }
    }

    __global__ void update_small_kernel(
        float *x,
        float *P,
        float *z,
        const float *measurement,
        const float *H,
        const float *R,
        int points,
        int dim_x,
        int dim_z)
    {
        const int point = blockIdx.x * blockDim.x + threadIdx.x;
        if (point >= points || dim_x > 4 || dim_z > 2)
        {
            return;
        }

        const std::size_t x_off = static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_x);
        const std::size_t z_off = static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_z);
        const std::size_t p_off = static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_x * dim_x);
        const std::size_t h_off = static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_z * dim_x);
        const std::size_t r_off = static_cast<std::size_t>(point) * static_cast<std::size_t>(dim_z * dim_z);

        float x_old[4] = {0.0f, 0.0f, 0.0f, 0.0f};
        float z_local[2] = {0.0f, 0.0f};
        float innov[2] = {0.0f, 0.0f};
        float hp[8];
        float s[4];
        float s_inv[4];
        float pht[8];
        float k[8];
        float x_new[4];
        float p_new[16];

        for (int row = 0; row < dim_x; ++row)
        {
            x_old[row] = x[x_off + static_cast<std::size_t>(row)];
        }
        for (int row = 0; row < dim_z; ++row)
        {
            const float value = measurement[z_off + static_cast<std::size_t>(row)];
            z_local[row] = value;
            z[z_off + static_cast<std::size_t>(row)] = value;
        }

        for (int row = 0; row < dim_z; ++row)
        {
            float hx = 0.0f;
            for (int col = 0; col < dim_x; ++col)
            {
                hx += H[h_off + static_cast<std::size_t>(row * dim_x + col)] * x_old[col];
            }
            innov[row] = z_local[row] - hx;
        }

        for (int row = 0; row < dim_z; ++row)
        {
            for (int col = 0; col < dim_x; ++col)
            {
                float value = 0.0f;
                for (int inner = 0; inner < dim_x; ++inner)
                {
                    value += H[h_off + static_cast<std::size_t>(row * dim_x + inner)] *
                             P[p_off + static_cast<std::size_t>(inner * dim_x + col)];
                }
                hp[row * 4 + col] = value;
            }
        }

        for (int row = 0; row < dim_z; ++row)
        {
            for (int col = 0; col < dim_z; ++col)
            {
                float value = 0.0f;
                for (int inner = 0; inner < dim_x; ++inner)
                {
                    value += hp[row * 4 + inner] *
                             H[h_off + static_cast<std::size_t>(col * dim_x + inner)];
                }
                s[row * 2 + col] = value + R[r_off + static_cast<std::size_t>(row * dim_z + col)];
            }
        }

        if (dim_z == 1)
        {
            if (!(fabsf(s[0]) > 0.0f))
            {
                return;
            }
            s_inv[0] = 1.0f / s[0];
        }
        else
        {
            const float det = s[0] * s[3] - s[1] * s[2];
            if (!(fabsf(det) > 0.0f))
            {
                return;
            }
            const float inv_det = 1.0f / det;
            s_inv[0] = s[3] * inv_det;
            s_inv[1] = -s[1] * inv_det;
            s_inv[2] = -s[2] * inv_det;
            s_inv[3] = s[0] * inv_det;
        }

        for (int row = 0; row < dim_x; ++row)
        {
            for (int col = 0; col < dim_z; ++col)
            {
                float value = 0.0f;
                for (int inner = 0; inner < dim_x; ++inner)
                {
                    value += P[p_off + static_cast<std::size_t>(row * dim_x + inner)] *
                             H[h_off + static_cast<std::size_t>(col * dim_x + inner)];
                }
                pht[row * 2 + col] = value;
            }
        }

        for (int row = 0; row < dim_x; ++row)
        {
            for (int col = 0; col < dim_z; ++col)
            {
                float value = 0.0f;
                for (int inner = 0; inner < dim_z; ++inner)
                {
                    value += pht[row * 2 + inner] * s_inv[inner * 2 + col];
                }
                k[row * 2 + col] = value;
            }
        }

        for (int row = 0; row < dim_x; ++row)
        {
            float value = x_old[row];
            for (int inner = 0; inner < dim_z; ++inner)
            {
                value += k[row * 2 + inner] * innov[inner];
            }
            x_new[row] = value;
        }

        for (int row = 0; row < dim_x; ++row)
        {
            for (int col = 0; col < dim_x; ++col)
            {
                float value = 0.0f;
                for (int mid = 0; mid < dim_x; ++mid)
                {
                    float ikh = row == mid ? 1.0f : 0.0f;
                    for (int z_index = 0; z_index < dim_z; ++z_index)
                    {
                        ikh -= k[row * 2 + z_index] *
                               H[h_off + static_cast<std::size_t>(z_index * dim_x + mid)];
                    }
                    value += ikh * P[p_off + static_cast<std::size_t>(mid * dim_x + col)];
                }
                p_new[row * 4 + col] = value;
            }
        }

        for (int row = 0; row < dim_x; ++row)
        {
            x[x_off + static_cast<std::size_t>(row)] = x_new[row];
        }
        for (int row = 0; row < dim_x; ++row)
        {
            for (int col = 0; col < dim_x; ++col)
            {
                P[p_off + static_cast<std::size_t>(row * dim_x + col)] = p_new[row * 4 + col];
            }
        }
    }

    template <int DimX, int DimZ>
    __global__ void update_fixed_kernel(
        float *x,
        float *P,
        float *z,
        const float *measurement,
        const float *H,
        const float *R,
        int points)
    {
        const int point = blockIdx.x * blockDim.x + threadIdx.x;
        if (point >= points)
        {
            return;
        }

        const std::size_t x_off = static_cast<std::size_t>(point) * DimX;
        const std::size_t z_off = static_cast<std::size_t>(point) * DimZ;
        const std::size_t p_off = static_cast<std::size_t>(point) * DimX * DimX;
        const std::size_t h_off = static_cast<std::size_t>(point) * DimZ * DimX;
        const std::size_t r_off = static_cast<std::size_t>(point) * DimZ * DimZ;

        float x_old[DimX];
        float z_local[DimZ];
        float innov[DimZ];
        float hp[DimZ * DimX];
        float s[DimZ * DimZ];
        float s_inv[DimZ * DimZ];
        float pht[DimX * DimZ];
        float k[DimX * DimZ];
        float x_new[DimX];
        float p_new[DimX * DimX];

#pragma unroll
        for (int row = 0; row < DimX; ++row)
        {
            x_old[row] = x[x_off + static_cast<std::size_t>(row)];
        }
#pragma unroll
        for (int row = 0; row < DimZ; ++row)
        {
            const float value = measurement[z_off + static_cast<std::size_t>(row)];
            z_local[row] = value;
            z[z_off + static_cast<std::size_t>(row)] = value;
        }

#pragma unroll
        for (int row = 0; row < DimZ; ++row)
        {
            float hx = 0.0f;
#pragma unroll
            for (int col = 0; col < DimX; ++col)
            {
                hx += H[h_off + static_cast<std::size_t>(row * DimX + col)] * x_old[col];
            }
            innov[row] = z_local[row] - hx;
        }

#pragma unroll
        for (int row = 0; row < DimZ; ++row)
        {
#pragma unroll
            for (int col = 0; col < DimX; ++col)
            {
                float value = 0.0f;
#pragma unroll
                for (int inner = 0; inner < DimX; ++inner)
                {
                    value += H[h_off + static_cast<std::size_t>(row * DimX + inner)] *
                             P[p_off + static_cast<std::size_t>(inner * DimX + col)];
                }
                hp[row * DimX + col] = value;
            }
        }

#pragma unroll
        for (int row = 0; row < DimZ; ++row)
        {
#pragma unroll
            for (int col = 0; col < DimZ; ++col)
            {
                float value = 0.0f;
#pragma unroll
                for (int inner = 0; inner < DimX; ++inner)
                {
                    value += hp[row * DimX + inner] *
                             H[h_off + static_cast<std::size_t>(col * DimX + inner)];
                }
                s[row * DimZ + col] =
                    value + R[r_off + static_cast<std::size_t>(row * DimZ + col)];
            }
        }

        if constexpr (DimZ == 1)
        {
            if (!(fabsf(s[0]) > 0.0f))
            {
                return;
            }
            s_inv[0] = 1.0f / s[0];
        }
        else
        {
            const float det = s[0] * s[3] - s[1] * s[2];
            if (!(fabsf(det) > 0.0f))
            {
                return;
            }
            const float inv_det = 1.0f / det;
            s_inv[0] = s[3] * inv_det;
            s_inv[1] = -s[1] * inv_det;
            s_inv[2] = -s[2] * inv_det;
            s_inv[3] = s[0] * inv_det;
        }

#pragma unroll
        for (int row = 0; row < DimX; ++row)
        {
#pragma unroll
            for (int col = 0; col < DimZ; ++col)
            {
                float value = 0.0f;
#pragma unroll
                for (int inner = 0; inner < DimX; ++inner)
                {
                    value += P[p_off + static_cast<std::size_t>(row * DimX + inner)] *
                             H[h_off + static_cast<std::size_t>(col * DimX + inner)];
                }
                pht[row * DimZ + col] = value;
            }
        }

#pragma unroll
        for (int row = 0; row < DimX; ++row)
        {
#pragma unroll
            for (int col = 0; col < DimZ; ++col)
            {
                float value = 0.0f;
#pragma unroll
                for (int inner = 0; inner < DimZ; ++inner)
                {
                    value += pht[row * DimZ + inner] * s_inv[inner * DimZ + col];
                }
                k[row * DimZ + col] = value;
            }
        }

#pragma unroll
        for (int row = 0; row < DimX; ++row)
        {
            float value = x_old[row];
#pragma unroll
            for (int inner = 0; inner < DimZ; ++inner)
            {
                value += k[row * DimZ + inner] * innov[inner];
            }
            x_new[row] = value;
        }

#pragma unroll
        for (int row = 0; row < DimX; ++row)
        {
#pragma unroll
            for (int col = 0; col < DimX; ++col)
            {
                float value = 0.0f;
#pragma unroll
                for (int mid = 0; mid < DimX; ++mid)
                {
                    float ikh = row == mid ? 1.0f : 0.0f;
#pragma unroll
                    for (int z_index = 0; z_index < DimZ; ++z_index)
                    {
                        ikh -= k[row * DimZ + z_index] *
                               H[h_off + static_cast<std::size_t>(z_index * DimX + mid)];
                    }
                    value += ikh * P[p_off + static_cast<std::size_t>(mid * DimX + col)];
                }
                p_new[row * DimX + col] = value;
            }
        }

#pragma unroll
        for (int row = 0; row < DimX; ++row)
        {
            x[x_off + static_cast<std::size_t>(row)] = x_new[row];
        }
#pragma unroll
        for (int index = 0; index < DimX * DimX; ++index)
        {
            P[p_off + static_cast<std::size_t>(index)] = p_new[index];
        }
    }
} // namespace

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace estimation
        {

            KalmanFilter::KalmanFilter(
                int dim_x,
                int dim_z,
                int dim_u,
                int points,
                const std::string &dtype)
                : dim_x_(dim_x),
                  dim_z_(dim_z),
                  dim_u_(dim_u),
                  points_(points),
                  dtype_(dtype)
            {
                detail::ensure_dim("dim_x", dim_x_);
                detail::ensure_dim("dim_z", dim_z_);
                detail::ensure_dim("dim_u", dim_u_, true);
                detail::ensure_dim("points", points_);
                detail::ensure_dtype(dtype_);

                x = ZxGpuRealArray(detail::state_vector_shape(points_, dim_x_), true);
                z = ZxGpuRealArray(detail::state_vector_shape(points_, dim_z_), true);
                B = ZxGpuRealArray(detail::rectangular_matrix_shape(points_, dim_x_, dim_u_), true);
                u = ZxGpuRealArray(detail::state_vector_shape(points_, dim_u_), true);
                H = ZxGpuRealArray(detail::rectangular_matrix_shape(points_, dim_z_, dim_x_), true);
                alpha_sq = ZxGpuRealArray(detail::state_vector_shape(points_, 1), true);

                core::RealArray alpha_host =
                    core::make_real_array(detail::state_vector_shape(points_, 1), 1.0f);
                alpha_sq = alpha_host;

                core::RealArray temp;
                detail::fill_identity(temp, points_, dim_x_);
                P = temp;
                Q = temp;
                F = temp;
                detail::fill_identity(temp, points_, dim_z_);
                R = temp;
            }

            void KalmanFilter::predict()
            {
                validate_filter_state(*this);

                if (dim_x_ <= 4 && dim_u_ <= 2)
                {
                    ScopedZxGpuEvents events;
                    g_last_kernel_ms = events.measure([&]() {
                        if (dim_x_ == 4 && dim_u_ == 2)
                        {
                            predict_fixed_kernel<4, 2><<<block_count(points_), kThreadsPerBlock>>>(
                                x.data(),
                                P.data(),
                                F.data(),
                                Q.data(),
                                B.data(),
                                u.data(),
                                nullptr,
                                false,
                                alpha_sq.data(),
                                points_);
                        }
                        else if (dim_x_ == 2 && dim_u_ == 1)
                        {
                            predict_fixed_kernel<2, 1><<<block_count(points_), kThreadsPerBlock>>>(
                                x.data(),
                                P.data(),
                                F.data(),
                                Q.data(),
                                B.data(),
                                u.data(),
                                nullptr,
                                false,
                                alpha_sq.data(),
                                points_);
                        }
                        else
                        {
                            predict_small_kernel<<<block_count(points_), kThreadsPerBlock>>>(
                                x.data(),
                                P.data(),
                                F.data(),
                                Q.data(),
                                B.data(),
                                u.data(),
                                nullptr,
                                false,
                                alpha_sq.data(),
                                points_,
                                dim_x_,
                                dim_u_);
                        }
                        check_kernel_launch("predict_small_kernel");
                    });
                    return;
                }

                g_workspace.scratch_a.resize(core::Shape{
                    static_cast<std::size_t>(points_),
                    static_cast<std::size_t>(dim_x_)});
                g_workspace.scratch_b.resize(core::Shape{
                    static_cast<std::size_t>(points_),
                    static_cast<std::size_t>(dim_x_ * dim_x_)});
                g_workspace.scratch_c.resize(core::Shape{
                    static_cast<std::size_t>(points_),
                    static_cast<std::size_t>(dim_x_ * dim_x_)});

                ScopedZxGpuEvents events;
                g_last_kernel_ms = events.measure([&]() {
                    predict_kernel<<<block_count(points_), kThreadsPerBlock>>>(
                        x.data(),
                        P.data(),
                        F.data(),
                        Q.data(),
                        B.data(),
                        u.data(),
                        alpha_sq.data(),
                        points_,
                        dim_x_,
                        dim_u_,
                        g_workspace.scratch_a.data(),
                        g_workspace.scratch_b.data(),
                        g_workspace.scratch_c.data());
                    check_kernel_launch("predict_kernel");
                });
            }

            void KalmanFilter::predict(const core::RealArrayLike &control)
            {
                const ZxGpuRealArray &control_device =
                    core::as_device_array(control, g_workspace.control_storage);
                validate_device_shape(
                    control_device.shape(),
                    detail::state_vector_shape(points_, dim_u_),
                    "control");
                validate_filter_state(*this);
                if (dim_x_ <= 4 && dim_u_ <= 2)
                {
                    ScopedZxGpuEvents events;
                    g_last_kernel_ms = events.measure([&]() {
                        if (dim_x_ == 4 && dim_u_ == 2)
                        {
                            predict_fixed_kernel<4, 2><<<block_count(points_), kThreadsPerBlock>>>(
                                x.data(),
                                P.data(),
                                F.data(),
                                Q.data(),
                                B.data(),
                                u.data(),
                                control_device.data(),
                                true,
                                alpha_sq.data(),
                                points_);
                        }
                        else if (dim_x_ == 2 && dim_u_ == 1)
                        {
                            predict_fixed_kernel<2, 1><<<block_count(points_), kThreadsPerBlock>>>(
                                x.data(),
                                P.data(),
                                F.data(),
                                Q.data(),
                                B.data(),
                                u.data(),
                                control_device.data(),
                                true,
                                alpha_sq.data(),
                                points_);
                        }
                        else
                        {
                            predict_small_kernel<<<block_count(points_), kThreadsPerBlock>>>(
                                x.data(),
                                P.data(),
                                F.data(),
                                Q.data(),
                                B.data(),
                                u.data(),
                                control_device.data(),
                                true,
                                alpha_sq.data(),
                                points_,
                                dim_x_,
                                dim_u_);
                        }
                        check_kernel_launch("predict_small_kernel(control)");
                    });
                    return;
                }
                copy_device_array(control_device, u);
                predict();
            }

            void KalmanFilter::update(const core::RealArrayLike &measurement)
            {
                const ZxGpuRealArray &measurement_device =
                    core::as_device_array(measurement, g_workspace.measurement_storage);
                validate_device_shape(
                    measurement_device.shape(),
                    detail::state_vector_shape(points_, dim_z_),
                    "measurement");
                validate_filter_state(*this);

                if (dim_x_ <= 4 && dim_z_ <= 2)
                {
                    ScopedZxGpuEvents events;
                    g_last_kernel_ms = events.measure([&]() {
                        if (dim_x_ == 4 && dim_z_ == 2)
                        {
                            update_fixed_kernel<4, 2><<<block_count(points_), kThreadsPerBlock>>>(
                                x.data(),
                                P.data(),
                                z.data(),
                                measurement_device.data(),
                                H.data(),
                                R.data(),
                                points_);
                        }
                        else if (dim_x_ == 2 && dim_z_ == 1)
                        {
                            update_fixed_kernel<2, 1><<<block_count(points_), kThreadsPerBlock>>>(
                                x.data(),
                                P.data(),
                                z.data(),
                                measurement_device.data(),
                                H.data(),
                                R.data(),
                                points_);
                        }
                        else
                        {
                            update_small_kernel<<<block_count(points_), kThreadsPerBlock>>>(
                                x.data(),
                                P.data(),
                                z.data(),
                                measurement_device.data(),
                                H.data(),
                                R.data(),
                                points_,
                                dim_x_,
                                dim_z_);
                        }
                        check_kernel_launch("update_small_kernel");
                    });
                    return;
                }

                copy_device_array(measurement_device, z);

                g_workspace.scratch_a.resize(core::Shape{
                    static_cast<std::size_t>(points_),
                    static_cast<std::size_t>(dim_z_)});
                g_workspace.scratch_b.resize(core::Shape{
                    static_cast<std::size_t>(points_),
                    static_cast<std::size_t>(dim_z_ * dim_x_)});
                g_workspace.scratch_c.resize(core::Shape{
                    static_cast<std::size_t>(points_),
                    static_cast<std::size_t>(dim_z_ * dim_z_)});
                g_workspace.scratch_d.resize(core::Shape{
                    static_cast<std::size_t>(points_),
                    static_cast<std::size_t>(dim_z_ * dim_z_)});
                g_workspace.scratch_e.resize(core::Shape{
                    static_cast<std::size_t>(points_),
                    static_cast<std::size_t>(dim_x_ * dim_z_)});
                g_workspace.scratch_f.resize(core::Shape{
                    static_cast<std::size_t>(points_),
                    static_cast<std::size_t>(dim_x_ * dim_z_)});
                g_workspace.scratch_g.resize(core::Shape{
                    static_cast<std::size_t>(points_),
                    static_cast<std::size_t>(dim_x_ * dim_x_)});
                g_workspace.scratch_h.resize(core::Shape{
                    static_cast<std::size_t>(points_),
                    static_cast<std::size_t>(dim_x_)});
                g_workspace.scratch_i.resize(core::Shape{
                    static_cast<std::size_t>(points_),
                    static_cast<std::size_t>(dim_x_ * dim_x_)});

                ScopedZxGpuEvents events;
                g_last_kernel_ms = events.measure([&]() {
                    update_kernel<<<block_count(points_), kThreadsPerBlock>>>(
                        x.data(),
                        P.data(),
                        z.data(),
                        H.data(),
                        R.data(),
                        points_,
                        dim_x_,
                        dim_z_,
                        g_workspace.scratch_a.data(),
                        g_workspace.scratch_b.data(),
                        g_workspace.scratch_c.data(),
                        g_workspace.scratch_d.data(),
                        g_workspace.scratch_e.data(),
                        g_workspace.scratch_f.data(),
                        g_workspace.scratch_g.data(),
                        g_workspace.scratch_h.data(),
                        g_workspace.scratch_i.data());
                    check_kernel_launch("update_kernel");
                });
            }

            int KalmanFilter::dim_x() const { return dim_x_; }
            int KalmanFilter::dim_z() const { return dim_z_; }
            int KalmanFilter::dim_u() const { return dim_u_; }
            int KalmanFilter::points() const { return points_; }
            const std::string &KalmanFilter::dtype() const { return dtype_; }

        } // namespace estimation

        namespace estimation_test_hooks
        {
            float consume_last_kernel_ms()
            {
                const float value = g_last_kernel_ms;
                g_last_kernel_ms = 0.0f;
                return value;
            }
        } // namespace estimation_test_hooks
    } // namespace zx_gpu_backend
} // namespace cusignal
