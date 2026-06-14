#include "estimation_test_support.hpp"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "../../../include/cusignal/core/helpers.hpp"
#include "../../../include/cusignal/estimation/estimation.hpp"
#include "../common/json.hpp"
#include "../common/report.hpp"

namespace fs = std::filesystem;

namespace cusignal
{
    namespace cuda_backend
    {
        namespace estimation_test_hooks
        {
            float consume_last_kernel_ms();
        }
    }
}

namespace
{
    using cusignal::core::CudaRealArray;
    using cusignal::core::RealArray;
    using cusignal::core::Shape;

    struct CliOptions
    {
        bool emit_report = false; // 是否在 data/reports 下输出 markdown/json/csv 报告
        bool gpu_only_perf = false; // perf 模式下跳过 CPU 输出与 CPU 计时
        std::string case_set = "accuracy"; // 用例集合：accuracy / perf / full / smoke
        int warmup = 5; // 基准统计前的不计时预热次数
        int repeat = 30; // 用于统计延迟的计时迭代次数
    };

    struct ErrorMetrics
    {
        float max_abs_error = 0.0f;
        float max_rel_error = 0.0f;
        float mixed_error = 0.0f;
        float rmse = 0.0f;
    };

    struct TimingStats
    {
        float mean_ms = 0.0f;
        float median_ms = 0.0f;
        float p95_ms = 0.0f;
        float min_ms = 0.0f;
        float max_ms = 0.0f;
        float std_ms = 0.0f;
    };

    struct Summary
    {
        bool pass = true;
        int accuracy_cases = 0;
        int perf_cases = 0;
        ErrorMetrics cpu_gpu_error;
        ErrorMetrics reference_error;
        std::optional<TimingStats> cpu_perf;
        std::optional<TimingStats> gpu_e2e_perf;
        std::optional<TimingStats> gpu_kernel_perf;
    };

    enum class Scenario
    {
        Defaults,
        Predict,
        PredictControl,
        Update,
        InvalidDtype,
        InvalidControlShape,
        InvalidMeasurementShape,
    };

    struct Case
    {
        std::string id;
        Scenario scenario;
        int dim_x = 2; // 状态向量维度
        int dim_z = 1; // 观测向量维度
        int dim_u = 0; // 控制输入维度
        int points = 1; // 重复 predict/update 的批次数
        std::string dtype = "float32"; // KalmanFilter 状态标量类型
        bool expect_exception = false; // 标记该用例是否应抛出异常
        float control_fill = 0.25f; // perf 控制向量填充值
        float measurement_fill = 0.5f; // perf 观测向量填充值
    };

    struct Snapshot
    {
        RealArray x;
        RealArray P;
        RealArray z;
        RealArray R;
        RealArray Q;
        RealArray F;
        RealArray H;
        RealArray B;
        RealArray u;
        RealArray alpha_sq;
    };

    fs::path repo_root()
    {
        return fs::path(CUSIGNAL_SOURCE_DIR);
    }

    fs::path generated_root()
    {
        return repo_root() / "data" / "generated" / "unit" / "estimation" / "kalman_filter";
    }

    fs::path report_root()
    {
        return repo_root() / "data" / "reports" / "unit" / "estimation" / "kalman_filter";
    }

    std::string read_text_file(const fs::path &path)
    {
        std::ifstream input(path);
        if (!input)
        {
            throw std::runtime_error("failed to open file: " + path.string());
        }
        std::ostringstream buffer;
        buffer << input.rdbuf();
        return buffer.str();
    }

    CliOptions parse_args(int argc, char **argv)
    {
        CliOptions options;
        for (int index = 1; index < argc; ++index)
        {
            const std::string arg = argv[index];
            if (arg == "--emit-report")
            {
                options.emit_report = true;
            }
            else if (arg == "--gpu-only-perf")
            {
                options.gpu_only_perf = true;
            }
            else if (arg == "--case-set" && index + 1 < argc)
            {
                options.case_set = argv[++index];
            }
            else if (arg == "--warmup" && index + 1 < argc)
            {
                options.warmup = std::stoi(argv[++index]);
            }
            else if (arg == "--repeat" && index + 1 < argc)
            {
                options.repeat = std::stoi(argv[++index]);
            }
        }
        return options;
    }

    std::string format_float(float value)
    {
        std::ostringstream stream;
        stream << std::scientific << std::setprecision(6) << value;
        return stream.str();
    }

    std::string format_fixed(float value)
    {
        std::ostringstream stream;
        stream << std::fixed << std::setprecision(3) << value;
        return stream.str();
    }

    RealArray make_array(const Shape &shape, const std::vector<float> &values)
    {
        RealArray array;
        array.shape = shape;
        array.values = values;
        return array;
    }

    ErrorMetrics compare_arrays(const RealArray &lhs, const RealArray &rhs)
    {
        if (lhs.shape != rhs.shape || lhs.values.size() != rhs.values.size())
        {
            throw std::runtime_error("shape mismatch while comparing estimation outputs");
        }
        ErrorMetrics metrics;
        if (lhs.values.empty())
        {
            return metrics;
        }
        float sq = 0.0;
        for (std::size_t index = 0; index < lhs.values.size(); ++index)
        {
            const float abs_error = std::fabs(static_cast<float>(lhs.values[index] - rhs.values[index]));
            const float denom = std::max(std::fabs(static_cast<float>(rhs.values[index])), 1e-12f);
            const float rel_error = abs_error / denom;
            metrics.max_abs_error = std::max(metrics.max_abs_error, static_cast<float>(abs_error));
            metrics.max_rel_error = std::max(metrics.max_rel_error, static_cast<float>(rel_error));
            sq += abs_error * abs_error;
        }
        metrics.rmse = static_cast<float>(std::sqrt(sq / static_cast<float>(lhs.values.size())));
        return metrics;
    }

    void merge_metrics(ErrorMetrics &dst, const ErrorMetrics &src)
    {
        dst.max_abs_error = std::max(dst.max_abs_error, src.max_abs_error);
        dst.max_rel_error = std::max(dst.max_rel_error, src.max_rel_error);
        dst.rmse = std::max(dst.rmse, src.rmse);
    }

    ErrorMetrics compare_snapshots(const Snapshot &lhs, const Snapshot &rhs)
    {
        ErrorMetrics metrics;
        merge_metrics(metrics, compare_arrays(lhs.x, rhs.x));
        merge_metrics(metrics, compare_arrays(lhs.P, rhs.P));
        merge_metrics(metrics, compare_arrays(lhs.z, rhs.z));
        merge_metrics(metrics, compare_arrays(lhs.R, rhs.R));
        merge_metrics(metrics, compare_arrays(lhs.Q, rhs.Q));
        merge_metrics(metrics, compare_arrays(lhs.F, rhs.F));
        merge_metrics(metrics, compare_arrays(lhs.H, rhs.H));
        merge_metrics(metrics, compare_arrays(lhs.B, rhs.B));
        merge_metrics(metrics, compare_arrays(lhs.u, rhs.u));
        merge_metrics(metrics, compare_arrays(lhs.alpha_sq, rhs.alpha_sq));
        return metrics;
    }

    TimingStats summarize(std::vector<float> samples)
    {
        TimingStats stats;
        if (samples.empty())
        {
            return stats;
        }
        std::sort(samples.begin(), samples.end());
        const float sum = std::accumulate(samples.begin(), samples.end(), 0.0f);
        stats.mean_ms = sum / static_cast<float>(samples.size());
        stats.median_ms = samples[samples.size() / 2];
        stats.p95_ms = samples[std::min(samples.size() - 1, (samples.size() * 95) / 100)];
        stats.min_ms = samples.front();
        stats.max_ms = samples.back();
        float variance_sum = 0.0;
        for (const float sample : samples)
        {
            const float diff = static_cast<float>(sample) - stats.mean_ms;
            variance_sum += diff * diff;
        }
        stats.std_ms = static_cast<float>(std::sqrt(variance_sum / static_cast<float>(samples.size())));
        return stats;
    }

    template <typename Callable>
    TimingStats measure(int warmup, int repeat, Callable callable)
    {
        for (int index = 0; index < warmup; ++index)
        {
            callable();
        }
        std::vector<float> samples;
        samples.reserve(static_cast<std::size_t>(repeat));
        for (int index = 0; index < repeat; ++index)
        {
            const auto start = std::chrono::steady_clock::now();
            callable();
            const auto stop = std::chrono::steady_clock::now();
            samples.push_back(
                std::chrono::duration<float, std::milli>(stop - start).count());
        }
        return summarize(std::move(samples));
    }

    CudaRealArray clone_device_array(const CudaRealArray &src)
    {
        CudaRealArray dst(src.shape(), false);
        if (src.size() != 0)
        {
            cusignal::core::throw_on_cuda_error(
                cudaMemcpy(
                    dst.data(),
                    src.data(),
                    src.size() * sizeof(float),
                    cudaMemcpyDeviceToDevice),
                "cudaMemcpy D2D(kalman clone)");
        }
        return dst;
    }

    void restore_device_array(
        const CudaRealArray &src,
        CudaRealArray &dst,
        const char *name)
    {
        if (src.shape() != dst.shape() || src.size() != dst.size())
        {
            throw std::runtime_error(std::string(name) + " shape changed during kalman perf reset");
        }
        if (src.size() == 0)
        {
            return;
        }
        cusignal::core::throw_on_cuda_error(
            cudaMemcpy(
                dst.data(),
                src.data(),
                src.size() * sizeof(float),
                cudaMemcpyDeviceToDevice),
            "cudaMemcpy D2D(kalman restore)");
    }

    void write_real_csv(const fs::path &path, const RealArray &array)
    {
        fs::create_directories(path.parent_path());
        std::ofstream output(path);
        output << "index,value\n";
        for (std::size_t index = 0; index < array.values.size(); ++index)
        {
            output << index << "," << array.values[index] << "\n";
        }
    }

    void write_reports(const Summary &summary, const CliOptions &options)
    {
        if (!options.emit_report)
        {
            return;
        }
        fs::create_directories(report_root());
        {
            std::ofstream output(report_root() / "latest_summary.md");
            output << "# kalman_filter\n\n";
            output << "- pass: " << (summary.pass ? "true" : "false") << "\n";
            output << "- accuracy_cases: " << summary.accuracy_cases << "\n";
            output << "- perf_cases: " << summary.perf_cases << "\n";
        }
        {
            cusignal_test::report::write_summary_only_metrics(
                "estimation",
                "kalman_filter",
                repo_root(),
                report_root(),
                __cplusplus,
                CUDART_VERSION,
                options,
                summary);
        }
        {
            std::ofstream output(report_root() / "latest_cases.csv");
            output << "case_id,category,pass\nsummary,aggregate," << (summary.pass ? "1" : "0") << "\n";
        }
    }

    std::vector<Case> accuracy_cases()
    {
        return {
            {"defaults", Scenario::Defaults, 2, 1, 0, 1, "float32", false},
            {"predict", Scenario::Predict, 2, 1, 0, 1, "float32", false},
            {"predict_control", Scenario::PredictControl, 2, 1, 1, 1, "float32", false},
            {"update", Scenario::Update, 2, 1, 0, 1, "float32", false},
            {"invalid_dtype", Scenario::InvalidDtype, 2, 1, 0, 1, "float16", true},
            {"invalid_control_shape", Scenario::InvalidControlShape, 2, 1, 1, 1, "float32", true},
            {"invalid_measurement_shape", Scenario::InvalidMeasurementShape, 2, 1, 0, 1, "float32", true},
        };
    }

    float get_optional_number(
        const cusignal_test::json::Object &object,
        const std::string &key,
        float fallback)
    {
        const auto iter = object.find(key);
        return iter == object.end() ? fallback : iter->second.as_number();
    }

    std::string get_optional_string(
        const cusignal_test::json::Object &object,
        const std::string &key,
        const std::string &fallback)
    {
        const auto iter = object.find(key);
        return iter == object.end() ? fallback : iter->second.as_string();
    }

    Case perf_case()
    {
        const fs::path manifest_path = generated_root() / "manifest.json";
        if (!fs::exists(manifest_path))
        {
            return {"perf_cycle", Scenario::PredictControl, 4, 2, 2, 64, "float32", false};
        }
        const auto root = cusignal_test::json::parse(read_text_file(manifest_path)).as_object();
        const auto &cases = root.at("perf_cases").as_array();
        if (cases.empty())
        {
            throw std::runtime_error("kalman_filter manifest has no perf_cases");
        }
        const auto &object = cases.front().as_object();
        Case out;
        out.id = get_optional_string(object, "id", "perf_cycle");
        out.scenario = Scenario::PredictControl;
        out.dim_x = static_cast<int>(get_optional_number(object, "dim_x", 4.0f));
        out.dim_z = static_cast<int>(get_optional_number(object, "dim_z", 2.0f));
        out.dim_u = static_cast<int>(get_optional_number(object, "dim_u", 2.0f));
        out.points = static_cast<int>(get_optional_number(object, "points", 64.0f));
        out.dtype = get_optional_string(object, "dtype", "float32");
        out.expect_exception = false;
        out.control_fill = get_optional_number(object, "control_fill", 0.25f);
        out.measurement_fill = get_optional_number(object, "measurement_fill", 0.5f);
        return out;
    }

    Snapshot capture_filter(const cusignal::cpu::estimation::KalmanFilter &filter)
    {
        return Snapshot{
            filter.x,
            filter.P,
            filter.z,
            filter.R,
            filter.Q,
            filter.F,
            filter.H,
            filter.B,
            filter.u,
            filter.alpha_sq,
        };
    }

    Snapshot capture_filter(const cusignal::cuda_backend::estimation::KalmanFilter &filter)
    {
        return Snapshot{
            filter.x.get(),
            filter.P.get(),
            filter.z.get(),
            filter.R.get(),
            filter.Q.get(),
            filter.F.get(),
            filter.H.get(),
            filter.B.get(),
            filter.u.get(),
            filter.alpha_sq.get(),
        };
    }

    void configure_predict_case(cusignal::cpu::estimation::KalmanFilter &filter)
    {
        filter.x = make_array(Shape{1, 2, 1}, {0.0f, 1.0f});
        filter.P = make_array(Shape{1, 2, 2}, {1.0f, 0.0f, 0.0f, 1.0f});
        filter.F = make_array(Shape{1, 2, 2}, {1.0f, 1.0f, 0.0f, 1.0f});
        filter.Q = make_array(Shape{1, 2, 2}, {0.1f, 0.0f, 0.0f, 0.2f});
    }

    void configure_predict_case(cusignal::cuda_backend::estimation::KalmanFilter &filter)
    {
        filter.x = make_array(Shape{1, 2, 1}, {0.0f, 1.0f});
        filter.P = make_array(Shape{1, 2, 2}, {1.0f, 0.0f, 0.0f, 1.0f});
        filter.F = make_array(Shape{1, 2, 2}, {1.0f, 1.0f, 0.0f, 1.0f});
        filter.Q = make_array(Shape{1, 2, 2}, {0.1f, 0.0f, 0.0f, 0.2f});
    }

    void configure_predict_control_case(cusignal::cpu::estimation::KalmanFilter &filter)
    {
        filter.x = make_array(Shape{1, 2, 1}, {1.0f, 2.0f});
        filter.P = make_array(Shape{1, 2, 2}, {1.0f, 0.0f, 0.0f, 1.0f});
        filter.F = make_array(Shape{1, 2, 2}, {1.0f, 0.0f, 0.0f, 1.0f});
        filter.Q = make_array(Shape{1, 2, 2}, {0.0f, 0.0f, 0.0f, 0.0f});
        filter.B = make_array(Shape{1, 2, 1}, {1.0f, 0.5f});
    }

    void configure_predict_control_case(cusignal::cuda_backend::estimation::KalmanFilter &filter)
    {
        filter.x = make_array(Shape{1, 2, 1}, {1.0f, 2.0f});
        filter.P = make_array(Shape{1, 2, 2}, {1.0f, 0.0f, 0.0f, 1.0f});
        filter.F = make_array(Shape{1, 2, 2}, {1.0f, 0.0f, 0.0f, 1.0f});
        filter.Q = make_array(Shape{1, 2, 2}, {0.0f, 0.0f, 0.0f, 0.0f});
        filter.B = make_array(Shape{1, 2, 1}, {1.0f, 0.5f});
    }

    void configure_update_case(cusignal::cpu::estimation::KalmanFilter &filter)
    {
        filter.x = make_array(Shape{1, 2, 1}, {1.0f, 1.0f});
        filter.P = make_array(Shape{1, 2, 2}, {2.1f, 1.0f, 1.0f, 1.2f});
        filter.H = make_array(Shape{1, 1, 2}, {1.0f, 0.0f});
        filter.R = make_array(Shape{1, 1, 1}, {0.5f});
    }

    void configure_update_case(cusignal::cuda_backend::estimation::KalmanFilter &filter)
    {
        filter.x = make_array(Shape{1, 2, 1}, {1.0f, 1.0f});
        filter.P = make_array(Shape{1, 2, 2}, {2.1f, 1.0f, 1.0f, 1.2f});
        filter.H = make_array(Shape{1, 1, 2}, {1.0f, 0.0f});
        filter.R = make_array(Shape{1, 1, 1}, {0.5f});
    }

    Snapshot expected_defaults()
    {
        return Snapshot{
            make_array(Shape{1, 2, 1}, {0.0f, 0.0f}),
            make_array(Shape{1, 2, 2}, {1.0f, 0.0f, 0.0f, 1.0f}),
            make_array(Shape{1, 1, 1}, {0.0f}),
            make_array(Shape{1, 1, 1}, {1.0f}),
            make_array(Shape{1, 2, 2}, {1.0f, 0.0f, 0.0f, 1.0f}),
            make_array(Shape{1, 2, 2}, {1.0f, 0.0f, 0.0f, 1.0f}),
            make_array(Shape{1, 1, 2}, {0.0f, 0.0f}),
            make_array(Shape{1, 2, 0}, {}),
            make_array(Shape{1, 0, 1}, {}),
            make_array(Shape{1, 1, 1}, {1.0f}),
        };
    }

    Snapshot expected_predict()
    {
        return Snapshot{
            make_array(Shape{1, 2, 1}, {1.0f, 1.0f}),
            make_array(Shape{1, 2, 2}, {2.1f, 1.0f, 1.0f, 1.2f}),
            make_array(Shape{1, 1, 1}, {0.0f}),
            make_array(Shape{1, 1, 1}, {1.0f}),
            make_array(Shape{1, 2, 2}, {0.1f, 0.0f, 0.0f, 0.2f}),
            make_array(Shape{1, 2, 2}, {1.0f, 1.0f, 0.0f, 1.0f}),
            make_array(Shape{1, 1, 2}, {0.0f, 0.0f}),
            make_array(Shape{1, 2, 0}, {}),
            make_array(Shape{1, 0, 1}, {}),
            make_array(Shape{1, 1, 1}, {1.0f}),
        };
    }

    Snapshot expected_predict_control()
    {
        return Snapshot{
            make_array(Shape{1, 2, 1}, {4.0f, 3.5f}),
            make_array(Shape{1, 2, 2}, {1.0f, 0.0f, 0.0f, 1.0f}),
            make_array(Shape{1, 1, 1}, {0.0f}),
            make_array(Shape{1, 1, 1}, {1.0f}),
            make_array(Shape{1, 2, 2}, {0.0f, 0.0f, 0.0f, 0.0f}),
            make_array(Shape{1, 2, 2}, {1.0f, 0.0f, 0.0f, 1.0f}),
            make_array(Shape{1, 1, 2}, {0.0f, 0.0f}),
            make_array(Shape{1, 2, 1}, {1.0f, 0.5f}),
            make_array(Shape{1, 1, 1}, {3.0f}),
            make_array(Shape{1, 1, 1}, {1.0f}),
        };
    }

    Snapshot expected_update()
    {
        return Snapshot{
            make_array(Shape{1, 2, 1}, {1.16153848f, 1.07692313f}),
            make_array(Shape{1, 2, 2}, {0.40384614f, 0.19230771f, 0.19230771f, 0.81538463f}),
            make_array(Shape{1, 1, 1}, {1.2f}),
            make_array(Shape{1, 1, 1}, {0.5f}),
            make_array(Shape{1, 2, 2}, {1.0f, 0.0f, 0.0f, 1.0f}),
            make_array(Shape{1, 2, 2}, {1.0f, 0.0f, 0.0f, 1.0f}),
            make_array(Shape{1, 1, 2}, {1.0f, 0.0f}),
            make_array(Shape{1, 2, 0}, {}),
            make_array(Shape{1, 0, 1}, {}),
            make_array(Shape{1, 1, 1}, {1.0f}),
        };
    }

    Snapshot run_case_cpu(const Case &test_case)
    {
        using Filter = cusignal::cpu::estimation::KalmanFilter;
        if (test_case.scenario == Scenario::InvalidDtype)
        {
            Filter filter(test_case.dim_x, test_case.dim_z, test_case.dim_u, test_case.points, test_case.dtype);
            return capture_filter(filter);
        }

        Filter filter(test_case.dim_x, test_case.dim_z, test_case.dim_u, test_case.points, test_case.dtype);
        switch (test_case.scenario)
        {
        case Scenario::Defaults:
            return capture_filter(filter);
        case Scenario::Predict:
            configure_predict_case(filter);
            filter.predict();
            return capture_filter(filter);
        case Scenario::PredictControl:
            configure_predict_control_case(filter);
            filter.predict(make_array(Shape{1, 1, 1}, {3.0f}));
            return capture_filter(filter);
        case Scenario::Update:
            configure_update_case(filter);
            filter.update(make_array(Shape{1, 1, 1}, {1.2f}));
            return capture_filter(filter);
        case Scenario::InvalidControlShape:
            configure_predict_control_case(filter);
            filter.predict(make_array(Shape{1, 2, 1}, {1.0f, 2.0f}));
            return capture_filter(filter);
        case Scenario::InvalidMeasurementShape:
            configure_update_case(filter);
            filter.update(make_array(Shape{1, 2, 1}, {1.0f, 2.0f}));
            return capture_filter(filter);
        case Scenario::InvalidDtype:
            break;
        }
        throw std::logic_error("unreachable");
    }

    Snapshot run_case_gpu(const Case &test_case)
    {
        using Filter = cusignal::cuda_backend::estimation::KalmanFilter;
        if (test_case.scenario == Scenario::InvalidDtype)
        {
            Filter filter(test_case.dim_x, test_case.dim_z, test_case.dim_u, test_case.points, test_case.dtype);
            return capture_filter(filter);
        }

        Filter filter(test_case.dim_x, test_case.dim_z, test_case.dim_u, test_case.points, test_case.dtype);
        switch (test_case.scenario)
        {
        case Scenario::Defaults:
            return capture_filter(filter);
        case Scenario::Predict:
            configure_predict_case(filter);
            filter.predict();
            return capture_filter(filter);
        case Scenario::PredictControl:
            configure_predict_control_case(filter);
            filter.predict(make_array(Shape{1, 1, 1}, {3.0f}));
            return capture_filter(filter);
        case Scenario::Update:
            configure_update_case(filter);
            filter.update(make_array(Shape{1, 1, 1}, {1.2f}));
            return capture_filter(filter);
        case Scenario::InvalidControlShape:
            configure_predict_control_case(filter);
            filter.predict(make_array(Shape{1, 2, 1}, {1.0f, 2.0f}));
            return capture_filter(filter);
        case Scenario::InvalidMeasurementShape:
            configure_update_case(filter);
            filter.update(make_array(Shape{1, 2, 1}, {1.0f, 2.0f}));
            return capture_filter(filter);
        case Scenario::InvalidDtype:
            break;
        }
        throw std::logic_error("unreachable");
    }

    Snapshot expected_for(const Case &test_case)
    {
        switch (test_case.scenario)
        {
        case Scenario::Defaults:
            return expected_defaults();
        case Scenario::Predict:
            return expected_predict();
        case Scenario::PredictControl:
            return expected_predict_control();
        case Scenario::Update:
            return expected_update();
        case Scenario::InvalidDtype:
        case Scenario::InvalidControlShape:
        case Scenario::InvalidMeasurementShape:
            return {};
        }
        throw std::logic_error("unreachable");
    }

    float speedup(const std::optional<TimingStats> &cpu, const std::optional<TimingStats> &gpu)
    {
        if (!cpu.has_value() || !gpu.has_value() || gpu->median_ms <= 0.0f)
        {
            return 0.0f;
        }
        return cpu->median_ms / gpu->median_ms;
    }

    Summary run_cases(const CliOptions &options)
    {
        Summary summary;
        if (options.case_set == "accuracy" || options.case_set == "full" || options.case_set == "smoke")
        {
            for (const Case &test_case : accuracy_cases())
            {
                summary.accuracy_cases += 1;
                bool cpu_exception = false;
                bool gpu_exception = false;
                Snapshot cpu_snapshot;
                Snapshot gpu_snapshot;
                try
                {
                    cpu_snapshot = run_case_cpu(test_case);
                }
                catch (const std::exception &)
                {
                    cpu_exception = true;
                }
                try
                {
                    gpu_snapshot = run_case_gpu(test_case);
                }
                catch (const std::exception &)
                {
                    gpu_exception = true;
                }

                if (test_case.expect_exception)
                {
                    summary.pass = summary.pass && cpu_exception && gpu_exception;
                    continue;
                }

                if (cpu_exception || gpu_exception)
                {
                    summary.pass = false;
                    continue;
                }

                const Snapshot expected = expected_for(test_case);
                const ErrorMetrics cpu_gpu = compare_snapshots(cpu_snapshot, gpu_snapshot);
                const ErrorMetrics cpu_ref = compare_snapshots(cpu_snapshot, expected);
                const ErrorMetrics gpu_ref = compare_snapshots(gpu_snapshot, expected);
                merge_metrics(summary.cpu_gpu_error, cpu_gpu);
                merge_metrics(summary.reference_error, cpu_ref);
                merge_metrics(summary.reference_error, gpu_ref);
                summary.pass = summary.pass &&
                               cpu_ref.max_abs_error <= 1e-4f &&
                               gpu_ref.max_abs_error <= 1e-4f;
            }
        }

        if (options.case_set == "perf" || options.case_set == "full" || options.case_set == "smoke")
        {
            summary.perf_cases = 1;
            const Case perf = perf_case();
            const RealArray control = make_array(
                Shape{
                    static_cast<std::size_t>(perf.points),
                    static_cast<std::size_t>(perf.dim_u),
                    1},
                std::vector<float>(
                    static_cast<std::size_t>(perf.points * perf.dim_u),
                    perf.control_fill));
            const RealArray measurement = make_array(
                Shape{
                    static_cast<std::size_t>(perf.points),
                    static_cast<std::size_t>(perf.dim_z),
                    1},
                std::vector<float>(
                    static_cast<std::size_t>(perf.points * perf.dim_z),
                    perf.measurement_fill));
            RealArray host_h = make_array(
                Shape{
                    static_cast<std::size_t>(perf.points),
                    static_cast<std::size_t>(perf.dim_z),
                    static_cast<std::size_t>(perf.dim_x)},
                std::vector<float>(
                    static_cast<std::size_t>(perf.points * perf.dim_z * perf.dim_x),
                    0.0f));
            RealArray host_r = make_array(
                Shape{
                    static_cast<std::size_t>(perf.points),
                    static_cast<std::size_t>(perf.dim_z),
                    static_cast<std::size_t>(perf.dim_z)},
                std::vector<float>(
                    static_cast<std::size_t>(perf.points * perf.dim_z * perf.dim_z),
                    0.0f));
            for (int point = 0; point < perf.points; ++point)
            {
                const std::size_t h_base =
                    static_cast<std::size_t>(point * perf.dim_z * perf.dim_x);
                for (int diag = 0; diag < std::min(perf.dim_z, perf.dim_x); ++diag)
                {
                    host_h.values[h_base + static_cast<std::size_t>(diag * perf.dim_x + diag)] = 1.0f;
                }
                const std::size_t r_base =
                    static_cast<std::size_t>(point * perf.dim_z * perf.dim_z);
                for (int diag = 0; diag < perf.dim_z; ++diag)
                {
                    host_r.values[r_base + static_cast<std::size_t>(diag * perf.dim_z + diag)] = 0.1f;
                }
            }

            if (!options.gpu_only_perf)
            {
                summary.cpu_perf = measure(options.warmup, options.repeat, [&]() {
                    cusignal::cpu::estimation::KalmanFilter filter(
                        perf.dim_x,
                        perf.dim_z,
                        perf.dim_u,
                        perf.points,
                        perf.dtype);
                    filter.H = host_h;
                    filter.R = host_r;
                    filter.predict(control);
                    filter.update(measurement);
                });
            }

            std::vector<float> kernel_samples;
            const CudaRealArray device_control = CudaRealArray::from_host(control);
            const CudaRealArray device_measurement = CudaRealArray::from_host(measurement);
            cusignal::cuda_backend::estimation::KalmanFilter gpu_filter(
                perf.dim_x,
                perf.dim_z,
                perf.dim_u,
                perf.points,
                perf.dtype);
            gpu_filter.H = host_h;
            gpu_filter.R = host_r;
            const CudaRealArray initial_x = clone_device_array(gpu_filter.x);
            const CudaRealArray initial_p = clone_device_array(gpu_filter.P);
            const CudaRealArray initial_z = clone_device_array(gpu_filter.z);
            const CudaRealArray initial_u = clone_device_array(gpu_filter.u);
            auto reset_gpu_filter = [&]() {
                restore_device_array(initial_x, gpu_filter.x, "x");
                restore_device_array(initial_p, gpu_filter.P, "P");
                restore_device_array(initial_z, gpu_filter.z, "z");
                restore_device_array(initial_u, gpu_filter.u, "u");
            };
            summary.gpu_e2e_perf = measure(options.warmup, options.repeat, [&]() {
                reset_gpu_filter();
                (void)cusignal::cuda_backend::estimation_test_hooks::consume_last_kernel_ms();
                gpu_filter.predict(device_control);
                float kernel_ms = cusignal::cuda_backend::estimation_test_hooks::consume_last_kernel_ms();
                gpu_filter.update(device_measurement);
                kernel_ms += cusignal::cuda_backend::estimation_test_hooks::consume_last_kernel_ms();
                kernel_samples.push_back(kernel_ms);
            });
            summary.gpu_kernel_perf = summarize(std::move(kernel_samples));

            if (options.emit_report)
            {
                if (!options.gpu_only_perf)
                {
                    fs::create_directories(generated_root() / "input");
                    write_real_csv(generated_root() / "input" / "perf_case__control.csv", control);
                    write_real_csv(generated_root() / "input" / "perf_case__measurement.csv", measurement);

                    cusignal::cuda_backend::estimation::KalmanFilter gpu_filter(
                        perf.dim_x,
                        perf.dim_z,
                        perf.dim_u,
                        perf.points,
                        perf.dtype);
                    gpu_filter.H = host_h;
                    gpu_filter.R = host_r;
                    gpu_filter.predict(control);
                    gpu_filter.update(measurement);

                    cusignal::cpu::estimation::KalmanFilter cpu_filter(
                        perf.dim_x,
                        perf.dim_z,
                        perf.dim_u,
                        perf.points,
                        perf.dtype);
                    cpu_filter.H = host_h;
                    cpu_filter.R = host_r;
                    cpu_filter.predict(control);
                    cpu_filter.update(measurement);
                    write_real_csv(generated_root() / "output_samples" / "perf_case__cpu__x.csv", cpu_filter.x);
                    write_real_csv(generated_root() / "output_samples" / "perf_case__cpu__P.csv", cpu_filter.P);
                    write_real_csv(generated_root() / "output_samples" / "perf_case__gpu__x.csv", gpu_filter.x.get());
                    write_real_csv(generated_root() / "output_samples" / "perf_case__gpu__P.csv", gpu_filter.P.get());
                }
            }
        }

        std::cout << "[estimation/kalman_filter] " << (summary.pass ? "PASS" : "FAIL")
                  << "  accuracy_cases=" << summary.accuracy_cases
                  << "  perf_cases=" << summary.perf_cases << "\n";
        std::cout << "cpu_gpu_error : max_abs=" << format_float(summary.cpu_gpu_error.max_abs_error)
                  << "  max_rel=" << format_float(summary.cpu_gpu_error.max_rel_error)
                  << "  rmse=" << format_float(summary.cpu_gpu_error.rmse) << "\n";
        std::cout << "reference_error : max_abs=" << format_float(summary.reference_error.max_abs_error)
                  << "  max_rel=" << format_float(summary.reference_error.max_rel_error)
                  << "  rmse=" << format_float(summary.reference_error.rmse) << "\n";
        if (summary.cpu_perf.has_value())
        {
            std::cout << "cpu_perf_ms   : median=" << format_fixed(summary.cpu_perf->median_ms)
                      << "  mean=" << format_fixed(summary.cpu_perf->mean_ms)
                      << "  p95=" << format_fixed(summary.cpu_perf->p95_ms) << "\n";
        }
        if (summary.gpu_e2e_perf.has_value())
        {
            std::cout << "gpu_perf_ms   : e2e_median=" << format_fixed(summary.gpu_e2e_perf->median_ms)
                      << "  kernel_median="
                      << format_fixed(summary.gpu_kernel_perf.has_value() ? summary.gpu_kernel_perf->median_ms : 0.0f)
                      << "  p95=" << format_fixed(summary.gpu_e2e_perf->p95_ms)
                      << "  e2e_speedup=" << format_fixed(speedup(summary.cpu_perf, summary.gpu_e2e_perf)) << "x"
                      << "  kernel_speedup=" << format_fixed(speedup(summary.cpu_perf, summary.gpu_kernel_perf)) << "x\n";
        }
        if (options.emit_report)
        {
            write_reports(summary, options);
            std::cout << "reports       : "
                      << (report_root() / "latest_summary.md").lexically_relative(repo_root()).string() << "\n";
        }
        return summary;
    }
} // namespace

int run_kalman_filter_tests(int argc, char **argv)
{
    const CliOptions options = parse_args(argc, argv);
    return run_cases(options).pass ? 0 : 1;
}
