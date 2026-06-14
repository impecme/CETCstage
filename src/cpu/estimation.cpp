#include "cusignal/estimation/estimation.hpp"

#include <algorithm>
#include <stdexcept>
#include <vector>

#include "../common/estimation_detail.hpp"

namespace
{
    using cusignal::core::RealArray;
    namespace detail = cusignal::estimation_detail;

    void validate_filter_state(
        const cusignal::cpu::estimation::KalmanFilter &filter)
    {
        detail::validate_member_shape(
            filter.x,
            detail::state_vector_shape(filter.points(), filter.dim_x()),
            "x");
        detail::validate_member_shape(
            filter.P,
            detail::square_matrix_shape(filter.points(), filter.dim_x()),
            "P");
        detail::validate_member_shape(
            filter.z,
            detail::state_vector_shape(filter.points(), filter.dim_z()),
            "z");
        detail::validate_member_shape(
            filter.R,
            detail::square_matrix_shape(filter.points(), filter.dim_z()),
            "R");
        detail::validate_member_shape(
            filter.Q,
            detail::square_matrix_shape(filter.points(), filter.dim_x()),
            "Q");
        detail::validate_member_shape(
            filter.F,
            detail::square_matrix_shape(filter.points(), filter.dim_x()),
            "F");
        detail::validate_member_shape(
            filter.H,
            detail::rectangular_matrix_shape(filter.points(), filter.dim_z(), filter.dim_x()),
            "H");
        detail::validate_member_shape(
            filter.B,
            detail::rectangular_matrix_shape(filter.points(), filter.dim_x(), filter.dim_u()),
            "B");
        detail::validate_member_shape(
            filter.u,
            detail::state_vector_shape(filter.points(), filter.dim_u()),
            "u");
        detail::validate_member_shape(
            filter.alpha_sq,
            detail::state_vector_shape(filter.points(), 1),
            "alpha_sq");
    }
} // namespace

namespace cusignal
{
    namespace cpu
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

                x = core::make_real_array(detail::state_vector_shape(points_, dim_x_), 0.0f);
                z = core::make_real_array(detail::state_vector_shape(points_, dim_z_), 0.0f);
                B = core::make_real_array(
                    detail::rectangular_matrix_shape(points_, dim_x_, dim_u_),
                    0.0f);
                u = core::make_real_array(detail::state_vector_shape(points_, dim_u_), 0.0f);
                H = core::make_real_array(
                    detail::rectangular_matrix_shape(points_, dim_z_, dim_x_),
                    0.0f);
                alpha_sq = core::make_real_array(detail::state_vector_shape(points_, 1), 1.0f);
                detail::fill_identity(P, points_, dim_x_);
                detail::fill_identity(Q, points_, dim_x_);
                detail::fill_identity(F, points_, dim_x_);
                detail::fill_identity(R, points_, dim_z_);
            }

            void KalmanFilter::predict()
            {
                validate_filter_state(*this);

                std::vector<float> x_new(static_cast<std::size_t>(dim_x_), 0.0f);
                std::vector<float> fp(static_cast<std::size_t>(dim_x_ * dim_x_), 0.0f);
                std::vector<float> p_new(static_cast<std::size_t>(dim_x_ * dim_x_), 0.0f);

                for (int point = 0; point < points_; ++point)
                {
                    const std::size_t x_off = detail::vector_offset(point, dim_x_);
                    const std::size_t p_off = detail::matrix_offset(point, dim_x_, dim_x_);
                    const std::size_t u_off = detail::vector_offset(point, dim_u_);
                    const std::size_t f_off = detail::matrix_offset(point, dim_x_, dim_x_);
                    const std::size_t q_off = detail::matrix_offset(point, dim_x_, dim_x_);
                    const std::size_t b_off = detail::matrix_offset(point, dim_x_, dim_u_);
                    const float alpha = alpha_sq.values[static_cast<std::size_t>(point)];

                    for (int row = 0; row < dim_x_; ++row)
                    {
                        float value = 0.0f;
                        for (int col = 0; col < dim_x_; ++col)
                        {
                            value +=
                                F.values[f_off + static_cast<std::size_t>(row * dim_x_ + col)] *
                                x.values[x_off + static_cast<std::size_t>(col)];
                        }
                        if (dim_u_ > 0)
                        {
                            for (int col = 0; col < dim_u_; ++col)
                            {
                                value +=
                                    B.values[b_off + static_cast<std::size_t>(row * dim_u_ + col)] *
                                    u.values[u_off + static_cast<std::size_t>(col)];
                            }
                        }
                        x_new[static_cast<std::size_t>(row)] = value;
                    }

                    for (int row = 0; row < dim_x_; ++row)
                    {
                        for (int col = 0; col < dim_x_; ++col)
                        {
                            float value = 0.0f;
                            for (int k = 0; k < dim_x_; ++k)
                            {
                                value +=
                                    F.values[f_off + static_cast<std::size_t>(row * dim_x_ + k)] *
                                    P.values[p_off + static_cast<std::size_t>(k * dim_x_ + col)];
                            }
                            fp[static_cast<std::size_t>(row * dim_x_ + col)] = value;
                        }
                    }

                    for (int row = 0; row < dim_x_; ++row)
                    {
                        for (int col = 0; col < dim_x_; ++col)
                        {
                            float value = 0.0f;
                            for (int k = 0; k < dim_x_; ++k)
                            {
                                value +=
                                    fp[static_cast<std::size_t>(row * dim_x_ + k)] *
                                    F.values[f_off + static_cast<std::size_t>(col * dim_x_ + k)];
                            }
                            p_new[static_cast<std::size_t>(row * dim_x_ + col)] =
                                alpha * value +
                                Q.values[q_off + static_cast<std::size_t>(row * dim_x_ + col)];
                        }
                    }

                    std::copy(x_new.begin(), x_new.end(), x.values.begin() + static_cast<std::ptrdiff_t>(x_off));
                    std::copy(p_new.begin(), p_new.end(), P.values.begin() + static_cast<std::ptrdiff_t>(p_off));
                }
            }

            void KalmanFilter::predict(const core::RealArray &control)
            {
                detail::validate_control_shape(control, points_, dim_u_);
                u = control;
                predict();
            }

            void KalmanFilter::update(const core::RealArray &measurement)
            {
                detail::validate_measurement_shape(measurement, points_, dim_z_);
                validate_filter_state(*this);
                z = measurement;

                std::vector<float> hx(static_cast<std::size_t>(dim_z_), 0.0f);
                std::vector<float> innovation(static_cast<std::size_t>(dim_z_), 0.0f);
                std::vector<float> hp(static_cast<std::size_t>(dim_z_ * dim_x_), 0.0f);
                std::vector<float> s(static_cast<std::size_t>(dim_z_ * dim_z_), 0.0f);
                std::vector<float> s_inv;
                std::vector<float> pht(static_cast<std::size_t>(dim_x_ * dim_z_), 0.0f);
                std::vector<float> k(static_cast<std::size_t>(dim_x_ * dim_z_), 0.0f);
                std::vector<float> kh(static_cast<std::size_t>(dim_x_ * dim_x_), 0.0f);
                std::vector<float> x_new(static_cast<std::size_t>(dim_x_), 0.0f);
                std::vector<float> p_new(static_cast<std::size_t>(dim_x_ * dim_x_), 0.0f);

                for (int point = 0; point < points_; ++point)
                {
                    const std::size_t x_off = detail::vector_offset(point, dim_x_);
                    const std::size_t z_off = detail::vector_offset(point, dim_z_);
                    const std::size_t p_off = detail::matrix_offset(point, dim_x_, dim_x_);
                    const std::size_t h_off = detail::matrix_offset(point, dim_z_, dim_x_);
                    const std::size_t r_off = detail::matrix_offset(point, dim_z_, dim_z_);

                    for (int row = 0; row < dim_z_; ++row)
                    {
                        float value = 0.0f;
                        for (int col = 0; col < dim_x_; ++col)
                        {
                            value +=
                                H.values[h_off + static_cast<std::size_t>(row * dim_x_ + col)] *
                                x.values[x_off + static_cast<std::size_t>(col)];
                        }
                        hx[static_cast<std::size_t>(row)] = value;
                        innovation[static_cast<std::size_t>(row)] =
                            z.values[z_off + static_cast<std::size_t>(row)] - value;
                    }

                    for (int row = 0; row < dim_z_; ++row)
                    {
                        for (int col = 0; col < dim_x_; ++col)
                        {
                            float value = 0.0f;
                            for (int inner = 0; inner < dim_x_; ++inner)
                            {
                                value +=
                                    H.values[h_off + static_cast<std::size_t>(row * dim_x_ + inner)] *
                                    P.values[p_off + static_cast<std::size_t>(inner * dim_x_ + col)];
                            }
                            hp[static_cast<std::size_t>(row * dim_x_ + col)] = value;
                        }
                    }

                    for (int row = 0; row < dim_z_; ++row)
                    {
                        for (int col = 0; col < dim_z_; ++col)
                        {
                            float value = 0.0f;
                            for (int inner = 0; inner < dim_x_; ++inner)
                            {
                                value +=
                                    hp[static_cast<std::size_t>(row * dim_x_ + inner)] *
                                    H.values[h_off + static_cast<std::size_t>(col * dim_x_ + inner)];
                            }
                            s[static_cast<std::size_t>(row * dim_z_ + col)] =
                                value + R.values[r_off + static_cast<std::size_t>(row * dim_z_ + col)];
                        }
                    }

                    s_inv = s;
                    detail::invert_matrix_in_place(s_inv, dim_z_);

                    for (int row = 0; row < dim_x_; ++row)
                    {
                        for (int col = 0; col < dim_z_; ++col)
                        {
                            float value = 0.0f;
                            for (int inner = 0; inner < dim_x_; ++inner)
                            {
                                value +=
                                    P.values[p_off + static_cast<std::size_t>(row * dim_x_ + inner)] *
                                    H.values[h_off + static_cast<std::size_t>(col * dim_x_ + inner)];
                            }
                            pht[static_cast<std::size_t>(row * dim_z_ + col)] = value;
                        }
                    }

                    for (int row = 0; row < dim_x_; ++row)
                    {
                        for (int col = 0; col < dim_z_; ++col)
                        {
                            float value = 0.0f;
                            for (int inner = 0; inner < dim_z_; ++inner)
                            {
                                value +=
                                    pht[static_cast<std::size_t>(row * dim_z_ + inner)] *
                                    s_inv[static_cast<std::size_t>(inner * dim_z_ + col)];
                            }
                            k[static_cast<std::size_t>(row * dim_z_ + col)] = value;
                        }
                    }

                    for (int row = 0; row < dim_x_; ++row)
                    {
                        float value = x.values[x_off + static_cast<std::size_t>(row)];
                        for (int inner = 0; inner < dim_z_; ++inner)
                        {
                            value +=
                                k[static_cast<std::size_t>(row * dim_z_ + inner)] *
                                innovation[static_cast<std::size_t>(inner)];
                        }
                        x_new[static_cast<std::size_t>(row)] = value;
                    }

                    for (int row = 0; row < dim_x_; ++row)
                    {
                        for (int col = 0; col < dim_x_; ++col)
                        {
                            float value = (row == col) ? 1.0f : 0.0f;
                            for (int inner = 0; inner < dim_z_; ++inner)
                            {
                                value -=
                                    k[static_cast<std::size_t>(row * dim_z_ + inner)] *
                                    H.values[h_off + static_cast<std::size_t>(inner * dim_x_ + col)];
                            }
                            kh[static_cast<std::size_t>(row * dim_x_ + col)] = value;
                        }
                    }

                    for (int row = 0; row < dim_x_; ++row)
                    {
                        for (int col = 0; col < dim_x_; ++col)
                        {
                            float value = 0.0f;
                            for (int inner = 0; inner < dim_x_; ++inner)
                            {
                                value +=
                                    kh[static_cast<std::size_t>(row * dim_x_ + inner)] *
                                    P.values[p_off + static_cast<std::size_t>(inner * dim_x_ + col)];
                            }
                            p_new[static_cast<std::size_t>(row * dim_x_ + col)] = value;
                        }
                    }

                    std::copy(x_new.begin(), x_new.end(), x.values.begin() + static_cast<std::ptrdiff_t>(x_off));
                    std::copy(p_new.begin(), p_new.end(), P.values.begin() + static_cast<std::ptrdiff_t>(p_off));
                }
            }

            int KalmanFilter::dim_x() const { return dim_x_; }
            int KalmanFilter::dim_z() const { return dim_z_; }
            int KalmanFilter::dim_u() const { return dim_u_; }
            int KalmanFilter::points() const { return points_; }
            const std::string &KalmanFilter::dtype() const { return dtype_; }

        } // namespace estimation
    } // namespace cpu
} // namespace cusignal
