#pragma once

#include <cublas_v2.h>
#include <cufft.h>
#include <cusolverDn.h>

#include <stdexcept>
#include <string>

#include "cusignal/core/platform_cuda_compat.hpp"

namespace cusignal
{
    namespace core
    {
        namespace platform
        {
            inline void throw_on_cufft_error(cufftResult status, const char *what)
            {
                if (status != CUFFT_SUCCESS)
                {
                    throw std::runtime_error(
                        std::string(what) + " [" + platform_name() + "]: cuFFT error code " +
                        std::to_string(static_cast<int>(status)));
                }
            }

            inline void throw_on_cublas_error(cublasStatus_t status, const char *what)
            {
                if (status != CUBLAS_STATUS_SUCCESS)
                {
                    throw std::runtime_error(
                        std::string(what) + " [" + platform_name() + "]: cuBLAS error code " +
                        std::to_string(static_cast<int>(status)));
                }
            }

            inline void throw_on_cusolver_error(cusolverStatus_t status, const char *what)
            {
                if (status != CUSOLVER_STATUS_SUCCESS)
                {
                    throw std::runtime_error(
                        std::string(what) + " [" + platform_name() + "]: cuSOLVER error code " +
                        std::to_string(static_cast<int>(status)));
                }
            }
        } // namespace platform
    } // namespace core
} // namespace cusignal
