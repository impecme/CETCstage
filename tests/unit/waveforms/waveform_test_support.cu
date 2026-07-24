#include "waveform_test_support.hpp"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iomanip>
#include <iostream>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <vector>

#include "../../../include/cusignal/waveforms/waveforms.hpp"
#include "../../../src/common/waveforms_detail.hpp"
#include "../common/live_perf.hpp"
#include "../common/json.hpp"
#include "../common/report.hpp"

namespace fs = std::filesystem;

namespace
{
    using cusignal::core::ComplexSignal;
    using cusignal::core::ZxGpuComplexSignal;
    using cusignal::core::ZxGpuRealSignal;
    using cusignal::core::Float16;
    using cusignal::core::RealSignal;
    using cusignal::core::Shape;
    using cusignal::waveforms_api::ChirpResult;
    using cusignal::waveforms_api::ZxGpuChirpResult;
    using cusignal::waveforms_api::ZxGpuGausspulseResult;
    using cusignal::waveforms_api::ZxGpuNdRealSignal;
    using cusignal::waveforms_api::GausspulseResult;
    using cusignal::waveforms_api::NdRealSignal;
    using ZxGpuUnitImpulseResult = std::variant<ZxGpuRealSignal, ZxGpuNdRealSignal>;

    constexpr int kThreadsPerBlock = 256; // 辅助 ZQ500 GPU kernel 的启动配置

    struct CliOptions
    {
        bool emit_report = false; // 是否在 data/reports 下输出 markdown/json/csv 报告
        bool gpu_only_perf = false; // perf 模式下跳过 CPU 输出与 CPU 计时
        bool verbose = false; // 是否在 stdout 打印逐用例诊断信息
        std::string case_set = "accuracy"; // 用例集合：accuracy / perf / full / smoke
        int warmup = 5; // 基准统计前的不计时预热次数
        int repeat = 30; // 用于统计延迟的计时迭代次数
    };

    struct ChannelData
    {
        std::string name;
        std::vector<std::size_t> shape;
        std::vector<float> values;
        std::vector<float> imag_values;
        bool is_complex = false;
    };

    struct OutputBundle
    {
        std::string kind;
        std::vector<ChannelData> channels;
    };

    struct ErrorMetrics
    {
        float max_abs_error = 0.0;
        float max_rel_error = 0.0;
        float mixed_error = 0.0;
        float rmse = 0.0;
        float l2_error = 0.0;
        bool exact_match = true;
        long long first_mismatch_index = -1;
        std::size_t compared_samples = 0;
    };

    struct TimingStats
    {
        float mean_ms = 0.0;
        float median_ms = 0.0;
        float p95_ms = 0.0;
        float min_ms = 0.0;
        float max_ms = 0.0;
        float std_ms = 0.0;
        std::vector<float> samples_ms;
    };

    struct Artifact
    {
        std::string role;
        fs::path path;
        std::string sha256;
    };

    struct CaseReport
    {
        std::string case_id;
        std::string category;
        std::size_t samples = 0;
        ErrorMetrics cpu_gpu_error;
        std::optional<ErrorMetrics> cpu_reference_error;
        std::optional<ErrorMetrics> gpu_reference_error;
        std::optional<TimingStats> cpu_perf;
        std::optional<TimingStats> gpu_e2e_perf;
        std::optional<TimingStats> gpu_kernel_perf;
        bool pass = true;
        std::string note;
        std::vector<Artifact> artifacts;
    };

    struct OperatorSummary
    {
        bool pass = true;
        int accuracy_cases = 0;
        int perf_cases = 0;
        ErrorMetrics cpu_gpu_error;
        std::optional<ErrorMetrics> reference_error;
        std::optional<TimingStats> cpu_perf;
        std::optional<TimingStats> gpu_e2e_perf;
        std::optional<TimingStats> gpu_kernel_perf;
        std::vector<std::string> failed_cases;
    };

    struct PerfGenerator
    {
        float start = 0.0; // 生成时间向量起点
        float stop = 0.0; // 生成时间向量终点
        std::size_t count = 0; // 生成时间向量采样点数
        bool endpoint = false; // 生成 linspace 时是否包含终点
    };

    struct ChirpCase
    {
        std::string id;
        std::string category;
        RealSignal t;
        float f0 = 0.0; // chirp 起始频率
        float t1 = 1.0; // chirp 达到 f1 的时刻
        float f1 = 0.0; // chirp 终止频率
        std::string method = "linear"; // chirp 扫频方法：linear/quadratic/logarithmic/hyperbolic
        float phi = 0.0; // 相位偏移（度）
        bool vertex_zero = true; // 二次 chirp 顶点位置选择开关
        std::string type = "real"; // 输出类型：real/complex
        float atol = 0.0; // 正确性校验的绝对误差容限
        float rtol = 0.0; // 正确性校验的相对误差容限
        std::string dtype = "float32"; // 兼容路径 dtype；float16 用例按 FP16 量化后比较
        fs::path expected_signal_file;
    };

    struct GausspulseCase
    {
        std::string id;
        std::string category;
        RealSignal t;
        float fc = 1000.0; // 中心频率
        float bw = 0.5; // 分数带宽
        float bwr = -6.0; // bw 对应参考电平（dB）
        float tpr = -60.0; // 时间功率参考电平（dB）
        bool retquad = false; // 是否额外返回正交分量
        bool retenv = false; // 是否额外返回包络
        float atol = 0.0; // 正确性校验的绝对误差容限
        float rtol = 0.0; // 正确性校验的相对误差容限
        std::string dtype = "float32"; // 兼容路径 dtype；float16 用例按 FP16 量化后比较
        fs::path expected_signal_file;
        fs::path expected_quadrature_file;
        fs::path expected_envelope_file;
    };

    struct SawtoothCase
    {
        std::string id;
        std::string category;
        RealSignal t;
        bool width_is_vector = false; // 当 width 来自逐样本向量时为 true
        float width_scalar = 1.0; // width_is_vector 为 false 时的标量 width
        RealSignal width_values;
        float atol = 0.0; // 正确性校验的绝对误差容限
        float rtol = 0.0; // 正确性校验的相对误差容限
        std::string dtype = "float32"; // 兼容路径 dtype；float16 用例按 FP16 量化后比较
        fs::path expected_signal_file;
    };

    struct SquareCase
    {
        std::string id;
        std::string category;
        RealSignal t;
        bool duty_is_vector = false; // 当 duty 来自逐样本向量时为 true
        float duty_scalar = 0.5; // duty_is_vector 为 false 时的标量占空比
        RealSignal duty_values;
        float atol = 0.0; // 正确性校验的绝对误差容限
        float rtol = 0.0; // 正确性校验的相对误差容限
        std::string dtype = "float32"; // 兼容路径 dtype；float16 用例按 FP16 量化后比较
        fs::path expected_signal_file;
    };

    struct UnitImpulseCase
    {
        std::string id;
        std::string category;
        bool is_nd = false; // 为 true 时生成 N 维脉冲张量
        std::size_t size = 0; // is_nd 为 false 时的一维输出长度
        Shape shape;
        std::string dtype = "float32"; // 输出 dtype 字符串
        std::string index_mode = "default"; // 索引格式：default/scalar/shape
        std::size_t scalar_index = 0; // index_mode=scalar 时的标量脉冲索引
        Shape shape_index;
        float atol = 0.0; // 正确性校验的绝对误差容限
        float rtol = 0.0; // 正确性校验的相对误差容限
        fs::path expected_signal_file;
    };

    fs::path repo_root()
    {
        return fs::path(CUSIGNAL_SOURCE_DIR);
    }

    fs::path reference_root(const std::string &op)
    {
        return repo_root() / "data" / "reference" / "unit" / "waveforms" / op;
    }

    fs::path generated_root(const std::string &op)
    {
        return cusignal_test::live_perf::generated_unit_root(
                   repo_root() / "data" / "generated" / "unit") /
               "waveforms" / op;
    }

    fs::path report_root(const std::string &op)
    {
        return repo_root() / "data" / ".reports_staging" / "unit" / "waveforms" / op;
    }

    fs::path module_report_root()
    {
        return repo_root() / "data" / ".reports_staging" / "unit" / "waveforms";
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

    std::string capture_command(const std::string &command)
    {
        std::string result;
        FILE *pipe = popen(command.c_str(), "r");
        if (pipe == nullptr)
        {
            return result;
        }

        char buffer[256];
        while (fgets(buffer, sizeof(buffer), pipe) != nullptr)
        {
            result += buffer;
        }
        pclose(pipe);

        while (!result.empty() && (result.back() == '\n' || result.back() == '\r'))
        {
            result.pop_back();
        }
        return result;
    }

    std::string sha256_of_file(const fs::path &path)
    {
        const std::string command = "sha256sum '" + path.string() + "' 2>/dev/null";
        const std::string output = capture_command(command);
        if (output.empty())
        {
            return {};
        }
        const std::size_t separator = output.find(' ');
        return separator == std::string::npos ? output : output.substr(0, separator);
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

    float median_speedup(
        const std::optional<TimingStats> &baseline,
        const std::optional<TimingStats> &candidate)
    {
        if (!baseline.has_value() || !candidate.has_value() || candidate->median_ms <= 0.0)
        {
            return 0.0;
        }
        return baseline->median_ms / candidate->median_ms;
    }

    std::vector<std::string> split_csv_line(const std::string &line)
    {
        std::vector<std::string> fields;
        std::stringstream stream(line);
        std::string field;
        while (std::getline(stream, field, ','))
        {
            fields.push_back(field);
        }
        return fields;
    }

    RealSignal read_real_csv(const fs::path &path)
    {
        std::ifstream input(path);
        if (!input)
        {
            throw std::runtime_error("failed to open csv: " + path.string());
        }

        RealSignal values;
        std::string line;
        std::getline(input, line); // 表头
        while (std::getline(input, line))
        {
            if (line.empty())
            {
                continue;
            }
            const auto fields = split_csv_line(line);
            values.push_back(std::stod(fields.at(fields.size() - 1)));
        }
        return values;
    }

    ComplexSignal read_complex_csv(const fs::path &path)
    {
        std::ifstream input(path);
        if (!input)
        {
            throw std::runtime_error("failed to open csv: " + path.string());
        }

        ComplexSignal values;
        std::string line;
        std::getline(input, line); // 表头
        while (std::getline(input, line))
        {
            if (line.empty())
            {
                continue;
            }
            const auto fields = split_csv_line(line);
            values.emplace_back(std::stod(fields.at(1)), std::stod(fields.at(2)));
        }
        return values;
    }

    void write_real_csv(const fs::path &path, const RealSignal &values)
    {
        fs::create_directories(path.parent_path());
        std::ofstream output(path);
        output << "index,value\n";
        for (std::size_t index = 0; index < values.size(); ++index)
        {
            output << index << ',' << std::setprecision(17) << values[index] << '\n';
        }
    }

    void write_complex_csv(const fs::path &path, const ComplexSignal &values)
    {
        fs::create_directories(path.parent_path());
        std::ofstream output(path);
        output << "index,real,imag\n";
        for (std::size_t index = 0; index < values.size(); ++index)
        {
            output << index << ',' << std::setprecision(17) << values[index].real() << ','
                   << values[index].imag() << '\n';
        }
    }

    void write_sample_bundle(
        const fs::path &base_dir,
        const std::string &case_id,
        const std::string &backend,
        const OutputBundle &bundle,
        std::vector<Artifact> *artifacts)
    {
        constexpr std::size_t kSampleLimit = 32;
        for (const ChannelData &channel : bundle.channels)
        {
            const fs::path path =
                base_dir / (case_id + "__" + backend + "__" + channel.name + ".csv");
            if (channel.is_complex)
            {
                ComplexSignal sample;
                const std::size_t limit =
                    std::min<std::size_t>(kSampleLimit, channel.values.size());
                sample.reserve(limit);
                for (std::size_t index = 0; index < limit; ++index)
                {
                    sample.emplace_back(channel.values[index], channel.imag_values[index]);
                }
                write_complex_csv(path, sample);
            }
            else
            {
                RealSignal sample(channel.values.begin(),
                                  channel.values.begin() +
                                      std::min<std::size_t>(kSampleLimit, channel.values.size()));
                write_real_csv(path, sample);
            }

            if (artifacts != nullptr)
            {
                artifacts->push_back(
                    Artifact{backend + "_" + channel.name, path, sha256_of_file(path)});
            }
        }
    }

    void write_input_csv(const fs::path &path, const RealSignal &values, std::vector<Artifact> *artifacts)
    {
        write_real_csv(path, values);
        if (artifacts != nullptr)
        {
            artifacts->push_back(Artifact{"input", path, sha256_of_file(path)});
        }
    }

    const cusignal_test::json::Object &as_object(const cusignal_test::json::Value &value)
    {
        if (!value.is_object())
        {
            throw std::runtime_error("expected JSON object");
        }
        return value.as_object();
    }

    const cusignal_test::json::Array &as_array(const cusignal_test::json::Value &value)
    {
        if (!value.is_array())
        {
            throw std::runtime_error("expected JSON array");
        }
        return value.as_array();
    }

    std::string get_string(const cusignal_test::json::Object &object, const std::string &key)
    {
        return object.at(key).as_string();
    }

    float get_number(const cusignal_test::json::Object &object, const std::string &key)
    {
        return object.at(key).as_number();
    }

    bool get_bool(const cusignal_test::json::Object &object, const std::string &key)
    {
        return object.at(key).as_bool();
    }

    std::optional<std::string> get_optional_string(
        const cusignal_test::json::Object &object,
        const std::string &key)
    {
        const auto iter = object.find(key);
        if (iter == object.end() || iter->second.is_null())
        {
            return std::nullopt;
        }
        return iter->second.as_string();
    }

    Shape get_size_array(const cusignal_test::json::Object &object, const std::string &key)
    {
        Shape values;
        for (const auto &item : as_array(object.at(key)))
        {
            values.push_back(static_cast<std::size_t>(item.as_number()));
        }
        return values;
    }

    RealSignal generate_linspace(const PerfGenerator &generator)
    {
        RealSignal values(generator.count, generator.start);
        if (generator.count == 0)
        {
            return values;
        }
        if (generator.count == 1)
        {
            values[0] = generator.start;
            return values;
        }

        const float divisor =
            generator.endpoint ? static_cast<float>(generator.count - 1) : generator.count;
        const float step = (generator.stop - generator.start) / divisor;
        for (std::size_t index = 0; index < generator.count; ++index)
        {
            values[index] = generator.start + step * static_cast<float>(index);
        }
        return values;
    }

    CliOptions parse_cli(int argc, char **argv)
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
            else if (arg == "--verbose")
            {
                options.verbose = true;
            }
            else if (arg == "--case-set")
            {
                if (index + 1 >= argc)
                {
                    throw std::runtime_error("--case-set requires a value");
                }
                options.case_set = argv[++index];
            }
            else if (arg == "--warmup")
            {
                if (index + 1 >= argc)
                {
                    throw std::runtime_error("--warmup requires a value");
                }
                options.warmup = std::stoi(argv[++index]);
            }
            else if (arg == "--repeat")
            {
                if (index + 1 >= argc)
                {
                    throw std::runtime_error("--repeat requires a value");
                }
                options.repeat = std::stoi(argv[++index]);
            }
            else
            {
                throw std::runtime_error("unknown argument: " + arg);
            }
        }
        return options;
    }

    bool include_accuracy_cases(const CliOptions &options)
    {
        return options.case_set == "accuracy" || options.case_set == "full" ||
               options.case_set == "smoke";
    }

    bool include_perf_cases(const CliOptions &options)
    {
        return options.case_set == "perf" || options.case_set == "full";
    }

    template <typename CaseType>
    std::vector<CaseType> limit_live_perf_cases(std::vector<CaseType> cases)
    {
        // The live demonstration measures one representative performance input
        // per operator. Formal perf/full runs leave every manifest case intact.
        if (std::getenv("CUSIGNAL_LIVE_DEMO_ONE_PERF_CASE") != nullptr && cases.size() > 1)
        {
            cases.resize(1);
        }
        return cases;
    }

    TimingStats compute_timing_stats(const std::vector<float> &samples)
    {
        TimingStats stats;
        stats.samples_ms = samples;
        if (samples.empty())
        {
            return stats;
        }

        const float total = std::accumulate(samples.begin(), samples.end(), 0.0);
        stats.mean_ms = total / static_cast<float>(samples.size());

        std::vector<float> sorted = samples;
        std::sort(sorted.begin(), sorted.end());
        stats.min_ms = sorted.front();
        stats.max_ms = sorted.back();
        stats.median_ms = sorted[sorted.size() / 2];
        const std::size_t p95_index =
            static_cast<std::size_t>(std::ceil(0.95 * static_cast<float>(sorted.size()))) - 1;
        stats.p95_ms = sorted[std::min<std::size_t>(p95_index, sorted.size() - 1)];

        float variance = 0.0;
        for (float sample : samples)
        {
            const float diff = sample - stats.mean_ms;
            variance += diff * diff;
        }
        variance /= static_cast<float>(samples.size());
        stats.std_ms = std::sqrt(variance);
        return stats;
    }

    template <typename Callable>
    TimingStats benchmark_host_latency(const CliOptions &options, Callable callable)
    {
        for (int warmup = 0; warmup < options.warmup; ++warmup)
        {
            callable();
        }

        std::vector<float> durations;
        durations.reserve(static_cast<std::size_t>(options.repeat));
        for (int repeat = 0; repeat < options.repeat; ++repeat)
        {
            const auto start = std::chrono::steady_clock::now();
            callable();
            const auto stop = std::chrono::steady_clock::now();
            durations.push_back(
                std::chrono::duration<float, std::milli>(stop - start).count());
        }
        return compute_timing_stats(durations);
    }

    void throw_on_zx_gpu_error(cudaError_t status, const char *what)
    {
        if (status != cudaSuccess)
        {
            throw std::runtime_error(std::string(what) + ": " + cudaGetErrorString(status));
        }
    }

    template <typename T>
    class DeviceBuffer
    {
    public:
        explicit DeviceBuffer(std::size_t size = 0)
        {
            if (size == 0)
            {
                return;
            }
            throw_on_zx_gpu_error(cudaMalloc(&data_, size * sizeof(T)), "cudaMalloc");
            size_ = size;
        }

        ~DeviceBuffer()
        {
            if (data_ != nullptr)
            {
                cudaFree(data_);
            }
        }

        DeviceBuffer(const DeviceBuffer &) = delete;
        DeviceBuffer &operator=(const DeviceBuffer &) = delete;

        T *get() { return data_; }
        const T *get() const { return data_; }
        std::size_t size() const { return size_; }

        void copy_from_host(const T *host, std::size_t count, const char *what)
        {
            if (count == 0)
            {
                return;
            }
            throw_on_zx_gpu_error(
                cudaMemcpy(data_, host, count * sizeof(T), cudaMemcpyHostToDevice),
                what);
        }

    private:
        T *data_ = nullptr;
        std::size_t size_ = 0;
    };

    int block_count(std::size_t size)
    {
        return size == 0 ? 0 : static_cast<int>((size + kThreadsPerBlock - 1) / kThreadsPerBlock);
    }

    __global__ void chirp_linear_real_kernel(
        const float *t,
        std::size_t size,
        float f0,
        float beta,
        float phi,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }
        const float phase = cusignal::waveforms_detail::linear_phase_from_beta(t[index], f0, beta);
        output[index] = cos(phase + phi);
    }

    __global__ void chirp_linear_complex_kernel(
        const float *t,
        std::size_t size,
        float f0,
        float beta,
        float phi,
        float2 *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }
        const float angle =
            cusignal::waveforms_detail::linear_phase_from_beta(t[index], f0, beta) + phi;
        output[index] = float2{cos(angle), sin(angle)};
    }

    __global__ void chirp_quadratic_kernel(
        const float *t,
        std::size_t size,
        float f0,
        float t1,
        float f1,
        float phi,
        bool vertex_zero,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }
        const float phase =
            cusignal::waveforms_detail::quadratic_phase(t[index], f0, t1, f1, vertex_zero);
        output[index] = cos(phase + phi);
    }

    __global__ void chirp_logarithmic_kernel(
        const float *t,
        std::size_t size,
        float f0,
        float t1,
        float f1,
        float phi,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }
        const float phase = cusignal::waveforms_detail::logarithmic_phase(t[index], f0, t1, f1);
        output[index] = cos(phase + phi);
    }

    __global__ void chirp_hyperbolic_kernel(
        const float *t,
        std::size_t size,
        float f0,
        float t1,
        float f1,
        float phi,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }
        const float phase = cusignal::waveforms_detail::hyperbolic_phase(t[index], f0, t1, f1);
        output[index] = cos(phase + phi);
    }

    template <bool ReturnQuadrature, bool ReturnEnvelope>
    __global__ void gausspulse_kernel(
        const float *t,
        std::size_t size,
        float a,
        float fc,
        float *signal,
        float *quadrature,
        float *envelope)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }
        cusignal::waveforms_detail::gausspulse_components<ReturnQuadrature, ReturnEnvelope>(
            t[index],
            a,
            fc,
            signal + index,
            ReturnQuadrature ? quadrature + index : nullptr,
            ReturnEnvelope ? envelope + index : nullptr);
    }

    __global__ void sawtooth_scalar_kernel(
        const float *t,
        std::size_t size,
        float width,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }
        output[index] = cusignal::waveforms_detail::sawtooth_value(t[index], width);
    }

    __global__ void sawtooth_vector_kernel(
        const float *t,
        const float *width,
        std::size_t size,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }
        output[index] = cusignal::waveforms_detail::sawtooth_value(t[index], width[index]);
    }

    __global__ void square_scalar_kernel(
        const float *t,
        std::size_t size,
        float duty,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }
        output[index] = cusignal::waveforms_detail::square_value(t[index], duty);
    }

    __global__ void square_vector_kernel(
        const float *t,
        const float *duty,
        std::size_t size,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }
        output[index] = cusignal::waveforms_detail::square_value(t[index], duty[index]);
    }

    __global__ void set_impulse_kernel(float *output, std::size_t flat_index)
    {
        output[flat_index] = 1.0;
    }

    template <typename Launch>
    TimingStats benchmark_gpu_kernel_latency(const CliOptions &options, Launch launch)
    {
        cudaEvent_t start {};
        cudaEvent_t stop {};
        throw_on_zx_gpu_error(cudaEventCreate(&start), "cudaEventCreate start");
        throw_on_zx_gpu_error(cudaEventCreate(&stop), "cudaEventCreate stop");

        for (int warmup = 0; warmup < options.warmup; ++warmup)
        {
            launch();
        }
        throw_on_zx_gpu_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize warmup");

        std::vector<float> samples;
        samples.reserve(static_cast<std::size_t>(options.repeat));
        for (int repeat = 0; repeat < options.repeat; ++repeat)
        {
            throw_on_zx_gpu_error(cudaEventRecord(start), "cudaEventRecord start");
            launch();
            throw_on_zx_gpu_error(cudaEventRecord(stop), "cudaEventRecord stop");
            throw_on_zx_gpu_error(cudaEventSynchronize(stop), "cudaEventSynchronize stop");
            float elapsed = 0.0f;
            throw_on_zx_gpu_error(cudaEventElapsedTime(&elapsed, start, stop), "cudaEventElapsedTime");
            samples.push_back(static_cast<float>(elapsed));
        }

        cudaEventDestroy(start);
        cudaEventDestroy(stop);
        return compute_timing_stats(samples);
    }

    OutputBundle make_real_bundle(const std::string &kind, const RealSignal &values)
    {
        ChannelData channel;
        channel.name = "signal";
        channel.shape = {values.size()};
        channel.values = values;
        return OutputBundle{kind, {channel}};
    }

    OutputBundle make_complex_bundle(const ComplexSignal &values)
    {
        ChannelData channel;
        channel.name = "signal";
        channel.shape = {values.size()};
        channel.values.reserve(values.size());
        channel.imag_values.reserve(values.size());
        channel.is_complex = true;
        for (const auto &value : values)
        {
            channel.values.push_back(value.real());
            channel.imag_values.push_back(value.imag());
        }
        return OutputBundle{"complex", {channel}};
    }

    OutputBundle to_output_bundle(const ChirpResult &result)
    {
        if (std::holds_alternative<RealSignal>(result))
        {
            return make_real_bundle("real", std::get<RealSignal>(result));
        }
        return make_complex_bundle(std::get<ComplexSignal>(result));
    }

    OutputBundle to_output_bundle(const ZxGpuChirpResult &result)
    {
        if (std::holds_alternative<ZxGpuRealSignal>(result))
        {
            return make_real_bundle("real", std::get<ZxGpuRealSignal>(result).get());
        }
        return make_complex_bundle(std::get<ZxGpuComplexSignal>(result).get());
    }

    OutputBundle to_output_bundle(const GausspulseResult &result)
    {
        if (std::holds_alternative<RealSignal>(result))
        {
            return make_real_bundle("real", std::get<RealSignal>(result));
        }
        if (std::holds_alternative<cusignal::waveforms_api::IqWaveform>(result))
        {
            const auto &value = std::get<cusignal::waveforms_api::IqWaveform>(result);
            return OutputBundle{
                "iq",
                {ChannelData{"signal", {value.signal.size()}, value.signal, {}, false},
                 ChannelData{"quadrature",
                             {value.quadrature.size()},
                             value.quadrature,
                             {},
                             false}}};
        }
        if (std::holds_alternative<cusignal::waveforms_api::IEnvWaveform>(result))
        {
            const auto &value = std::get<cusignal::waveforms_api::IEnvWaveform>(result);
            return OutputBundle{
                "ienv",
                {ChannelData{"signal", {value.signal.size()}, value.signal, {}, false},
                 ChannelData{"envelope", {value.envelope.size()}, value.envelope, {}, false}}};
        }

        const auto &value = std::get<cusignal::core::WaveformBundle>(result);
        return OutputBundle{
            "bundle",
            {ChannelData{"signal", {value.signal.size()}, value.signal, {}, false},
             ChannelData{"quadrature", {value.quadrature.size()}, value.quadrature, {}, false},
             ChannelData{"envelope", {value.envelope.size()}, value.envelope, {}, false}}};
    }

    OutputBundle to_output_bundle(const ZxGpuGausspulseResult &result)
    {
        if (std::holds_alternative<ZxGpuRealSignal>(result))
        {
            return make_real_bundle("real", std::get<ZxGpuRealSignal>(result).get());
        }
        if (std::holds_alternative<cusignal::waveforms_api::ZxGpuIqWaveform>(result))
        {
            const auto &value = std::get<cusignal::waveforms_api::ZxGpuIqWaveform>(result);
            return OutputBundle{
                "iq",
                {ChannelData{"signal", {value.signal.size()}, value.signal.get(), {}, false},
                 ChannelData{"quadrature",
                             {value.quadrature.size()},
                             value.quadrature.get(),
                             {},
                             false}}};
        }
        if (std::holds_alternative<cusignal::waveforms_api::ZxGpuIEnvWaveform>(result))
        {
            const auto &value = std::get<cusignal::waveforms_api::ZxGpuIEnvWaveform>(result);
            return OutputBundle{
                "ienv",
                {ChannelData{"signal", {value.signal.size()}, value.signal.get(), {}, false},
                 ChannelData{"envelope", {value.envelope.size()}, value.envelope.get(), {}, false}}};
        }

        const auto &value = std::get<cusignal::core::ZxGpuWaveformBundle>(result);
        return OutputBundle{
            "bundle",
            {ChannelData{"signal", {value.signal.size()}, value.signal.get(), {}, false},
             ChannelData{"quadrature", {value.quadrature.size()}, value.quadrature.get(), {}, false},
             ChannelData{"envelope", {value.envelope.size()}, value.envelope.get(), {}, false}}};
    }

    OutputBundle to_output_bundle(const RealSignal &result)
    {
        return make_real_bundle("real", result);
    }

    OutputBundle to_output_bundle(const ZxGpuRealSignal &result)
    {
        return make_real_bundle("real", result.get());
    }

    OutputBundle to_output_bundle(const NdRealSignal &result)
    {
        ChannelData channel;
        channel.name = "signal";
        channel.shape = result.shape;
        channel.values = result.values;
        return OutputBundle{"ndreal", {channel}};
    }

    OutputBundle to_output_bundle(const ZxGpuNdRealSignal &result)
    {
        ChannelData channel;
        channel.name = "signal";
        channel.shape = result.shape;
        channel.values = result.values.get();
        return OutputBundle{"ndreal", {channel}};
    }

    OutputBundle to_output_bundle(const ZxGpuUnitImpulseResult &result)
    {
        if (std::holds_alternative<ZxGpuRealSignal>(result))
        {
            return to_output_bundle(std::get<ZxGpuRealSignal>(result));
        }
        return to_output_bundle(std::get<ZxGpuNdRealSignal>(result));
    }

    OutputBundle to_output_bundle(const OutputBundle &result)
    {
        return result;
    }

    float quantize_float16(float value)
    {
        return __half2float(Float16(value));
    }

    OutputBundle apply_dtype_quantization(const OutputBundle &bundle, const std::string &dtype)
    {
        if (dtype == "float32")
        {
            return bundle;
        }
        if (dtype != "float16")
        {
            throw std::runtime_error("unsupported waveforms dtype compatibility case: " + dtype);
        }

        OutputBundle quantized = bundle;
        for (ChannelData &channel : quantized.channels)
        {
            if (channel.is_complex)
            {
                throw std::runtime_error("float16 compatibility case must use real waveforms output");
            }
            for (float &value : channel.values)
            {
                value = quantize_float16(value);
            }
        }
        return quantized;
    }

    OutputBundle load_expected_real_bundle(const fs::path &path, const std::string &kind)
    {
        return make_real_bundle(kind, read_real_csv(path));
    }

    OutputBundle load_expected_chirp(const ChirpCase &test_case)
    {
        if (test_case.expected_signal_file.empty())
        {
            return {};
        }
        if (test_case.type == "complex")
        {
            return make_complex_bundle(read_complex_csv(test_case.expected_signal_file));
        }
        return load_expected_real_bundle(test_case.expected_signal_file, "real");
    }

    OutputBundle load_expected_gausspulse(const GausspulseCase &test_case)
    {
        if (test_case.expected_signal_file.empty())
        {
            return {};
        }

        if (test_case.retquad && test_case.retenv)
        {
            return OutputBundle{
                "bundle",
                {ChannelData{"signal",
                             {read_real_csv(test_case.expected_signal_file).size()},
                             read_real_csv(test_case.expected_signal_file),
                             {},
                             false},
                 ChannelData{"quadrature",
                             {read_real_csv(test_case.expected_quadrature_file).size()},
                             read_real_csv(test_case.expected_quadrature_file),
                             {},
                             false},
                 ChannelData{"envelope",
                             {read_real_csv(test_case.expected_envelope_file).size()},
                             read_real_csv(test_case.expected_envelope_file),
                             {},
                             false}}};
        }
        if (test_case.retquad)
        {
            return OutputBundle{
                "iq",
                {ChannelData{"signal",
                             {read_real_csv(test_case.expected_signal_file).size()},
                             read_real_csv(test_case.expected_signal_file),
                             {},
                             false},
                 ChannelData{"quadrature",
                             {read_real_csv(test_case.expected_quadrature_file).size()},
                             read_real_csv(test_case.expected_quadrature_file),
                             {},
                             false}}};
        }
        if (test_case.retenv)
        {
            return OutputBundle{
                "ienv",
                {ChannelData{"signal",
                             {read_real_csv(test_case.expected_signal_file).size()},
                             read_real_csv(test_case.expected_signal_file),
                             {},
                             false},
                 ChannelData{"envelope",
                             {read_real_csv(test_case.expected_envelope_file).size()},
                             read_real_csv(test_case.expected_envelope_file),
                             {},
                             false}}};
        }
        return load_expected_real_bundle(test_case.expected_signal_file, "real");
    }

    OutputBundle load_expected_signal(const fs::path &path)
    {
        if (path.empty())
        {
            return {};
        }
        return load_expected_real_bundle(path, "real");
    }

    OutputBundle load_expected_unit_impulse(const UnitImpulseCase &test_case)
    {
        if (test_case.expected_signal_file.empty())
        {
            return {};
        }
        if (test_case.is_nd)
        {
            ChannelData channel;
            channel.name = "signal";
            channel.shape = test_case.shape;
            channel.values = read_real_csv(test_case.expected_signal_file);
            return OutputBundle{"ndreal", {channel}};
        }
        return load_expected_real_bundle(test_case.expected_signal_file, "real");
    }

    ErrorMetrics compare_output_bundles(
        const OutputBundle &actual,
        const OutputBundle &expected,
        float atol,
        float rtol)
    {
        if (actual.kind != expected.kind)
        {
            throw std::runtime_error("output kind mismatch: " + actual.kind + " vs " + expected.kind);
        }
        if (actual.channels.size() != expected.channels.size())
        {
            throw std::runtime_error("output channel count mismatch");
        }

        ErrorMetrics metrics;
        const float effective_atol = std::max(atol, 1.0e-5f);
        const float effective_rtol = std::max(rtol, 1.0e-5f);
        const float mixed_zero_floor = effective_atol;
        float squared_sum = 0.0;
        std::size_t global_index = 0;

        for (std::size_t channel_index = 0; channel_index < actual.channels.size(); ++channel_index)
        {
            const ChannelData &actual_channel = actual.channels[channel_index];
            const ChannelData &expected_channel = expected.channels[channel_index];
            if (actual_channel.shape != expected_channel.shape)
            {
                throw std::runtime_error("output shape mismatch");
            }
            if (actual_channel.values.size() != expected_channel.values.size() ||
                actual_channel.imag_values.size() != expected_channel.imag_values.size() ||
                actual_channel.is_complex != expected_channel.is_complex)
            {
                throw std::runtime_error("output value layout mismatch");
            }

            for (std::size_t index = 0; index < actual_channel.values.size(); ++index, ++global_index)
            {
                const float real_diff =
                    actual_channel.values[index] - expected_channel.values[index];
                const float imag_diff =
                    actual_channel.is_complex
                        ? actual_channel.imag_values[index] - expected_channel.imag_values[index]
                        : 0.0;
                const float abs_diff = std::sqrt(real_diff * real_diff + imag_diff * imag_diff);
                const float expected_norm =
                    actual_channel.is_complex
                        ? std::sqrt(expected_channel.values[index] * expected_channel.values[index] +
                                    expected_channel.imag_values[index] * expected_channel.imag_values[index])
                        : std::fabs(expected_channel.values[index]);
                const float threshold = effective_atol + effective_rtol * expected_norm;
                const float rel_error = expected_norm == 0.0 ? abs_diff : abs_diff / expected_norm;
                const float mixed_error = expected_norm <= mixed_zero_floor ? abs_diff : rel_error;

                metrics.max_abs_error = std::max(metrics.max_abs_error, abs_diff);
                metrics.max_rel_error = std::max(metrics.max_rel_error, rel_error);
                metrics.mixed_error = std::max(metrics.mixed_error, mixed_error);
                squared_sum += abs_diff * abs_diff;
                ++metrics.compared_samples;
                if (abs_diff > threshold)
                {
                    metrics.exact_match = false;
                    if (metrics.first_mismatch_index < 0)
                    {
                        metrics.first_mismatch_index = static_cast<long long>(global_index);
                    }
                }
            }
        }

        metrics.l2_error = std::sqrt(squared_sum);
        metrics.rmse = metrics.compared_samples == 0
                           ? 0.0
                           : std::sqrt(squared_sum / static_cast<float>(metrics.compared_samples));
        if (metrics.max_rel_error > 1.0e-2f &&
            metrics.max_abs_error <= 1.0e-3f &&
            metrics.rmse <= 1.0e-4f)
        {
            metrics.mixed_error = metrics.max_abs_error;
        }
        return metrics;
    }

    void assert_condition(bool condition, const std::string &message)
    {
        if (!condition)
        {
            throw std::runtime_error(message);
        }
    }

    std::string summary_line(const OperatorSummary &summary, const std::string &op)
    {
        std::ostringstream stream;
        stream << "[waveforms/" << op << "] " << (summary.pass ? "PASS" : "FAIL")
               << "  accuracy_cases=" << summary.accuracy_cases
               << "  perf_cases=" << summary.perf_cases;
        if (!summary.pass && !summary.failed_cases.empty())
        {
            stream << "  failed=";
            for (std::size_t index = 0; index < summary.failed_cases.size(); ++index)
            {
                if (index != 0)
                {
                    stream << ';';
                }
                stream << summary.failed_cases[index];
            }
        }
        return stream.str();
    }

    OperatorSummary summarize_cases(const std::vector<CaseReport> &cases)
    {
        OperatorSummary summary;
        std::vector<float> cpu_perf_medians;
        std::vector<float> gpu_e2e_perf_medians;
        std::vector<float> gpu_kernel_perf_medians;
        bool has_reference = false;
        float reference_max_abs = 0.0;
        float reference_max_rel = 0.0;
        float reference_mixed = 0.0;
        float reference_rmse = 0.0;
        float reference_l2 = 0.0;

        for (const CaseReport &report : cases)
        {
            if (report.category == "accuracy")
            {
                ++summary.accuracy_cases;
            }
            if (report.category == "perf")
            {
                ++summary.perf_cases;
            }
            if (!report.pass)
            {
                summary.pass = false;
                summary.failed_cases.push_back(report.case_id);
            }
            summary.cpu_gpu_error.max_abs_error =
                std::max(summary.cpu_gpu_error.max_abs_error, report.cpu_gpu_error.max_abs_error);
            summary.cpu_gpu_error.max_rel_error =
                std::max(summary.cpu_gpu_error.max_rel_error, report.cpu_gpu_error.max_rel_error);
            summary.cpu_gpu_error.mixed_error =
                std::max(summary.cpu_gpu_error.mixed_error, report.cpu_gpu_error.mixed_error);
            summary.cpu_gpu_error.rmse = std::max(summary.cpu_gpu_error.rmse, report.cpu_gpu_error.rmse);
            summary.cpu_gpu_error.l2_error =
                std::max(summary.cpu_gpu_error.l2_error, report.cpu_gpu_error.l2_error);
            summary.cpu_gpu_error.exact_match =
                summary.cpu_gpu_error.exact_match && report.cpu_gpu_error.exact_match;

            if (report.cpu_reference_error.has_value())
            {
                has_reference = true;
                reference_max_abs =
                    std::max(reference_max_abs, report.cpu_reference_error->max_abs_error);
                reference_max_rel =
                    std::max(reference_max_rel, report.cpu_reference_error->max_rel_error);
                reference_mixed =
                    std::max(reference_mixed, report.cpu_reference_error->mixed_error);
                reference_rmse = std::max(reference_rmse, report.cpu_reference_error->rmse);
                reference_l2 = std::max(reference_l2, report.cpu_reference_error->l2_error);
            }
            if (report.gpu_reference_error.has_value())
            {
                has_reference = true;
                reference_max_abs =
                    std::max(reference_max_abs, report.gpu_reference_error->max_abs_error);
                reference_max_rel =
                    std::max(reference_max_rel, report.gpu_reference_error->max_rel_error);
                reference_mixed =
                    std::max(reference_mixed, report.gpu_reference_error->mixed_error);
                reference_rmse = std::max(reference_rmse, report.gpu_reference_error->rmse);
                reference_l2 = std::max(reference_l2, report.gpu_reference_error->l2_error);
            }

            if (report.cpu_perf.has_value())
            {
                cpu_perf_medians.push_back(report.cpu_perf->median_ms);
            }
            if (report.gpu_e2e_perf.has_value())
            {
                gpu_e2e_perf_medians.push_back(report.gpu_e2e_perf->median_ms);
            }
            if (report.gpu_kernel_perf.has_value())
            {
                gpu_kernel_perf_medians.push_back(report.gpu_kernel_perf->median_ms);
            }
        }

        if (has_reference)
        {
            summary.reference_error = ErrorMetrics{};
            summary.reference_error->max_abs_error = reference_max_abs;
            summary.reference_error->max_rel_error = reference_max_rel;
            summary.reference_error->mixed_error = reference_mixed;
            summary.reference_error->rmse = reference_rmse;
            summary.reference_error->l2_error = reference_l2;
        }
        if (!cpu_perf_medians.empty())
        {
            summary.cpu_perf = compute_timing_stats(cpu_perf_medians);
        }
        if (!gpu_e2e_perf_medians.empty())
        {
            summary.gpu_e2e_perf = compute_timing_stats(gpu_e2e_perf_medians);
        }
        if (!gpu_kernel_perf_medians.empty())
        {
            summary.gpu_kernel_perf = compute_timing_stats(gpu_kernel_perf_medians);
        }

        return summary;
    }

    void write_operator_report(
        const std::string &op,
        const CliOptions &options,
        const std::vector<CaseReport> &cases)
    {
        const OperatorSummary summary = summarize_cases(cases);
        cusignal_test::report::WritePolicy policy;
        policy.emit_case_reference_errors = false;
        policy.emit_case_notes = false;
        cusignal_test::report::write_operator_report(
            "waveforms",
            op,
            repo_root(),
            report_root(op),
            __cplusplus,
            CUDART_VERSION,
            options,
            summary,
            cases,
            policy);
    }

    void update_module_reports()
    {
        cusignal_test::report::update_module_reports("waveforms", module_report_root());
    }

    void print_operator_terminal_summary(const std::string &op, const OperatorSummary &summary)
    {
        std::cout << summary_line(summary, op) << '\n';
        std::cout << "cpu_gpu_error : max_abs=" << format_float(summary.cpu_gpu_error.max_abs_error)
                  << "  max_rel=" << format_float(summary.cpu_gpu_error.max_rel_error)
                  << "  mixed=" << format_float(summary.cpu_gpu_error.mixed_error)
                  << "  rmse=" << format_float(summary.cpu_gpu_error.rmse) << '\n';
        if (summary.reference_error.has_value())
        {
            std::cout << "reference_error : max_abs="
                      << format_float(summary.reference_error->max_abs_error)
                      << "  max_rel=" << format_float(summary.reference_error->max_rel_error)
                      << "  mixed=" << format_float(summary.reference_error->mixed_error)
                      << "  rmse=" << format_float(summary.reference_error->rmse) << '\n';
        }
        if (summary.cpu_perf.has_value())
        {
            std::cout << "cpu_perf_ms   : median=" << format_fixed(summary.cpu_perf->median_ms)
                      << "  mean=" << format_fixed(summary.cpu_perf->mean_ms)
                      << "  p95=" << format_fixed(summary.cpu_perf->p95_ms) << '\n';
        }
        else
        {
            std::cout << "cpu_perf_ms   : not_run (accuracy-only; use perf/full case set for timing)\n";
        }
        if (summary.gpu_e2e_perf.has_value())
        {
            const float e2e_speedup = median_speedup(summary.cpu_perf, summary.gpu_e2e_perf);
            const float kernel_speedup =
                median_speedup(summary.cpu_perf, summary.gpu_kernel_perf);
            std::cout << "gpu_perf_ms   : e2e_median="
                      << format_fixed(summary.gpu_e2e_perf->median_ms)
                      << "  kernel_median="
                      << (summary.gpu_kernel_perf.has_value()
                              ? format_fixed(summary.gpu_kernel_perf->median_ms)
                              : "n/a")
                      << "  p95=" << format_fixed(summary.gpu_e2e_perf->p95_ms)
                      << "  e2e_speedup=" << format_fixed(e2e_speedup) << "x"
                      << "  kernel_speedup="
                      << (summary.gpu_kernel_perf.has_value() && summary.cpu_perf.has_value()
                              ? format_fixed(kernel_speedup) + "x"
                              : "n/a")
                      << '\n';
        }
        else
        {
            std::cout << "gpu_perf_ms   : not_run (accuracy-only; use perf/full case set for timing)\n";
        }
        std::cout << "reports       : data/.reports_staging/unit/waveforms/" << op << "/latest_summary.md\n";
    }

    std::vector<ChirpCase> load_chirp_cases(const fs::path &manifest_path, const std::string &category)
    {
        std::vector<ChirpCase> cases;
        const auto manifest = cusignal_test::json::parse(read_text_file(manifest_path));
        const auto &root = as_object(manifest);
        const auto &case_array =
            as_array(root.at(category == "accuracy" ? "accuracy_cases" : "perf_cases"));
        const fs::path base = manifest_path.parent_path();

        for (const auto &item : case_array)
        {
            const auto &object = as_object(item);
            ChirpCase test_case;
            test_case.id = get_string(object, "id");
            test_case.category = category;
            test_case.f0 = get_number(object, "f0"); // chirp 起始频率
            test_case.t1 = get_number(object, "t1"); // chirp 达到 f1 的时刻
            test_case.f1 = get_number(object, "f1"); // chirp 终止频率
            test_case.method = get_string(object, "method"); // 扫频方法
            test_case.phi = get_number(object, "phi"); // 相位偏移（度）
            test_case.vertex_zero = get_bool(object, "vertex_zero"); // 二次顶点选择开关
            test_case.type = get_string(object, "type"); // 输出类型
            test_case.atol = get_number(object, "atol"); // 绝对误差容限
            test_case.rtol = get_number(object, "rtol"); // 相对误差容限
            test_case.dtype = get_optional_string(object, "dtype").value_or("float32"); // 兼容 dtype

            if (const auto input_file = get_optional_string(object, "t_file"))
            {
                test_case.t = read_real_csv(base / *input_file);
            }
            else
            {
                const auto &generator = as_object(object.at("t_generator"));
                PerfGenerator perf;
                perf.start = get_number(generator, "start"); // t 生成器起点
                perf.stop = get_number(generator, "stop"); // t 生成器终点
                perf.count = static_cast<std::size_t>(get_number(generator, "count")); // t 生成器采样点数
                perf.endpoint = get_bool(generator, "endpoint"); // 是否包含终点
                test_case.t = generate_linspace(perf);
            }

            if (const auto expected = get_optional_string(object, "expected_signal_file"))
            {
                test_case.expected_signal_file = base / *expected;
            }
            cases.push_back(std::move(test_case));
        }

        return cases;
    }

    std::vector<GausspulseCase> load_gausspulse_cases(
        const fs::path &manifest_path,
        const std::string &category)
    {
        std::vector<GausspulseCase> cases;
        const auto manifest = cusignal_test::json::parse(read_text_file(manifest_path));
        const auto &root = as_object(manifest);
        const auto &case_array =
            as_array(root.at(category == "accuracy" ? "accuracy_cases" : "perf_cases"));
        const fs::path base = manifest_path.parent_path();

        for (const auto &item : case_array)
        {
            const auto &object = as_object(item);
            GausspulseCase test_case;
            test_case.id = get_string(object, "id");
            test_case.category = category;
            test_case.fc = get_number(object, "fc"); // 中心频率
            test_case.bw = get_number(object, "bw"); // 分数带宽
            test_case.bwr = get_number(object, "bwr"); // bw 参考电平
            test_case.tpr = get_number(object, "tpr"); // 时间功率参考电平
            test_case.retquad = get_bool(object, "retquad"); // 返回正交通道开关
            test_case.retenv = get_bool(object, "retenv"); // 返回包络通道开关
            test_case.atol = get_number(object, "atol"); // 绝对误差容限
            test_case.rtol = get_number(object, "rtol"); // 相对误差容限
            test_case.dtype = get_optional_string(object, "dtype").value_or("float32"); // 兼容 dtype

            if (const auto input_file = get_optional_string(object, "t_file"))
            {
                test_case.t = read_real_csv(base / *input_file);
            }
            else
            {
                const auto &generator = as_object(object.at("t_generator"));
                PerfGenerator perf;
                perf.start = get_number(generator, "start"); // t 生成器起点
                perf.stop = get_number(generator, "stop"); // t 生成器终点
                perf.count = static_cast<std::size_t>(get_number(generator, "count")); // t 生成器采样点数
                perf.endpoint = get_bool(generator, "endpoint"); // 是否包含终点
                test_case.t = generate_linspace(perf);
            }

            if (const auto value = get_optional_string(object, "expected_signal_file"))
            {
                test_case.expected_signal_file = base / *value;
            }
            if (const auto value = get_optional_string(object, "expected_quadrature_file"))
            {
                test_case.expected_quadrature_file = base / *value;
            }
            if (const auto value = get_optional_string(object, "expected_envelope_file"))
            {
                test_case.expected_envelope_file = base / *value;
            }
            cases.push_back(std::move(test_case));
        }
        return cases;
    }

    template <typename CaseType>
    std::vector<CaseType> load_scalar_wave_cases(
        const fs::path &manifest_path,
        const std::string &category,
        const std::string &value_file_key,
        const std::string &generator_key)
    {
        std::vector<CaseType> cases;
        const auto manifest = cusignal_test::json::parse(read_text_file(manifest_path));
        const auto &root = as_object(manifest);
        const auto &case_array =
            as_array(root.at(category == "accuracy" ? "accuracy_cases" : "perf_cases"));
        const fs::path base = manifest_path.parent_path();

        for (const auto &item : case_array)
        {
            const auto &object = as_object(item);
            CaseType test_case;
            test_case.id = get_string(object, "id");
            test_case.category = category;
            test_case.atol = get_number(object, "atol"); // 绝对误差容限
            test_case.rtol = get_number(object, "rtol"); // 相对误差容限
            test_case.dtype = get_optional_string(object, "dtype").value_or("float32"); // 兼容 dtype
            if (const auto input_file = get_optional_string(object, "t_file"))
            {
                test_case.t = read_real_csv(base / *input_file);
            }
            else
            {
                const auto &generator = as_object(object.at("t_generator"));
                PerfGenerator perf;
                perf.start = get_number(generator, "start"); // t 生成器起点
                perf.stop = get_number(generator, "stop"); // t 生成器终点
                perf.count = static_cast<std::size_t>(get_number(generator, "count")); // t 生成器采样点数
                perf.endpoint = get_bool(generator, "endpoint"); // 是否包含终点
                test_case.t = generate_linspace(perf);
            }

            if (const auto value_file = get_optional_string(object, value_file_key))
            {
                if constexpr (std::is_same_v<CaseType, SawtoothCase>)
                {
                    test_case.width_is_vector = true;
                    test_case.width_values = read_real_csv(base / *value_file);
                }
                else
                {
                    test_case.duty_is_vector = true;
                    test_case.duty_values = read_real_csv(base / *value_file);
                }
            }
            else
            {
                const float scalar = get_number(object, generator_key);
                if constexpr (std::is_same_v<CaseType, SawtoothCase>)
                {
                    test_case.width_scalar = scalar;
                }
                else
                {
                    test_case.duty_scalar = scalar;
                }
            }

            if (const auto expected = get_optional_string(object, "expected_signal_file"))
            {
                test_case.expected_signal_file = base / *expected;
            }
            cases.push_back(std::move(test_case));
        }
        return cases;
    }

    std::vector<UnitImpulseCase> load_unit_impulse_cases(
        const fs::path &manifest_path,
        const std::string &category)
    {
        std::vector<UnitImpulseCase> cases;
        const auto manifest = cusignal_test::json::parse(read_text_file(manifest_path));
        const auto &root = as_object(manifest);
        const auto &case_array =
            as_array(root.at(category == "accuracy" ? "accuracy_cases" : "perf_cases"));
        const fs::path base = manifest_path.parent_path();

        for (const auto &item : case_array)
        {
            const auto &object = as_object(item);
            UnitImpulseCase test_case;
            test_case.id = get_string(object, "id");
            test_case.category = category;
            test_case.is_nd = get_bool(object, "is_nd"); // 输出维度选择开关
            test_case.dtype = get_string(object, "dtype"); // 输出 dtype
            test_case.index_mode = get_string(object, "index_mode"); // 索引格式选择开关
            test_case.atol = get_number(object, "atol"); // 绝对误差容限
            test_case.rtol = get_number(object, "rtol"); // 相对误差容限
            if (test_case.is_nd)
            {
                test_case.shape = get_size_array(object, "shape");
                if (test_case.index_mode == "shape")
                {
                    test_case.shape_index = get_size_array(object, "index_shape");
                }
                else if (test_case.index_mode == "scalar")
                {
                    test_case.scalar_index =
                        static_cast<std::size_t>(get_number(object, "scalar_index"));
                }
            }
            else
            {
                test_case.size = static_cast<std::size_t>(get_number(object, "size"));
                if (test_case.index_mode == "scalar")
                {
                    test_case.scalar_index =
                        static_cast<std::size_t>(get_number(object, "scalar_index"));
                }
            }
            if (const auto expected = get_optional_string(object, "expected_signal_file"))
            {
                test_case.expected_signal_file = base / *expected;
            }
            cases.push_back(std::move(test_case));
        }
        return cases;
    }

    ChirpResult run_cpu(const ChirpCase &test_case)
    {
        return cusignal::cpu::waveforms::chirp(
            test_case.t,
            test_case.f0,
            test_case.t1,
            test_case.f1,
            test_case.method,
            test_case.phi,
            test_case.vertex_zero,
            test_case.type);
    }

    ZxGpuChirpResult run_gpu(const ChirpCase &test_case)
    {
        return cusignal::zx_gpu_backend::waveforms::chirp(
            test_case.t,
            test_case.f0,
            test_case.t1,
            test_case.f1,
            test_case.method,
            test_case.phi,
            test_case.vertex_zero,
            test_case.type);
    }

    ZxGpuChirpResult run_gpu(const ChirpCase &test_case, const ZxGpuRealSignal &device_t)
    {
        return cusignal::zx_gpu_backend::waveforms::chirp(
            device_t,
            test_case.f0,
            test_case.t1,
            test_case.f1,
            test_case.method,
            test_case.phi,
            test_case.vertex_zero,
            test_case.type);
    }

    GausspulseResult run_cpu(const GausspulseCase &test_case)
    {
        return cusignal::cpu::waveforms::gausspulse(
            test_case.t,
            test_case.fc,
            test_case.bw,
            test_case.bwr,
            test_case.tpr,
            test_case.retquad,
            test_case.retenv);
    }

    ZxGpuGausspulseResult run_gpu(const GausspulseCase &test_case)
    {
        return cusignal::zx_gpu_backend::waveforms::gausspulse(
            test_case.t,
            test_case.fc,
            test_case.bw,
            test_case.bwr,
            test_case.tpr,
            test_case.retquad,
            test_case.retenv);
    }

    ZxGpuGausspulseResult run_gpu(const GausspulseCase &test_case, const ZxGpuRealSignal &device_t)
    {
        return cusignal::zx_gpu_backend::waveforms::gausspulse(
            device_t,
            test_case.fc,
            test_case.bw,
            test_case.bwr,
            test_case.tpr,
            test_case.retquad,
            test_case.retenv);
    }

    RealSignal run_cpu(const SawtoothCase &test_case)
    {
        return test_case.width_is_vector
                   ? cusignal::cpu::waveforms::sawtooth(test_case.t, test_case.width_values)
                   : cusignal::cpu::waveforms::sawtooth(test_case.t, test_case.width_scalar);
    }

    ZxGpuRealSignal run_gpu(const SawtoothCase &test_case)
    {
        return test_case.width_is_vector
                   ? cusignal::zx_gpu_backend::waveforms::sawtooth(test_case.t, test_case.width_values)
                   : cusignal::zx_gpu_backend::waveforms::sawtooth(test_case.t, test_case.width_scalar);
    }

    ZxGpuRealSignal run_gpu(
        const SawtoothCase &test_case,
        const ZxGpuRealSignal &device_t,
        const ZxGpuRealSignal *device_width)
    {
        return test_case.width_is_vector
                   ? cusignal::zx_gpu_backend::waveforms::sawtooth(device_t, *device_width)
                   : cusignal::zx_gpu_backend::waveforms::sawtooth(device_t, test_case.width_scalar);
    }

    RealSignal run_cpu(const SquareCase &test_case)
    {
        return test_case.duty_is_vector
                   ? cusignal::cpu::waveforms::square(test_case.t, test_case.duty_values)
                   : cusignal::cpu::waveforms::square(test_case.t, test_case.duty_scalar);
    }

    ZxGpuRealSignal run_gpu(const SquareCase &test_case)
    {
        return test_case.duty_is_vector
                   ? cusignal::zx_gpu_backend::waveforms::square(test_case.t, test_case.duty_values)
                   : cusignal::zx_gpu_backend::waveforms::square(test_case.t, test_case.duty_scalar);
    }

    ZxGpuRealSignal run_gpu(
        const SquareCase &test_case,
        const ZxGpuRealSignal &device_t,
        const ZxGpuRealSignal *device_duty)
    {
        return test_case.duty_is_vector
                   ? cusignal::zx_gpu_backend::waveforms::square(device_t, *device_duty)
                   : cusignal::zx_gpu_backend::waveforms::square(device_t, test_case.duty_scalar);
    }

    OutputBundle run_cpu(const UnitImpulseCase &test_case)
    {
        if (!test_case.is_nd)
        {
            if (test_case.index_mode == "mid")
            {
                return to_output_bundle(cusignal::cpu::waveforms::unit_impulse(
                    test_case.size, std::string("mid"), test_case.dtype));
            }
            if (test_case.index_mode == "scalar")
            {
                return to_output_bundle(cusignal::cpu::waveforms::unit_impulse(
                    test_case.size, test_case.scalar_index, test_case.dtype));
            }
            return to_output_bundle(
                cusignal::cpu::waveforms::unit_impulse(test_case.size, 0, test_case.dtype));
        }

        if (test_case.index_mode == "mid")
        {
            return to_output_bundle(cusignal::cpu::waveforms::unit_impulse(
                test_case.shape, "mid", test_case.dtype));
        }
        if (test_case.index_mode == "shape")
        {
            return to_output_bundle(cusignal::cpu::waveforms::unit_impulse(
                test_case.shape, test_case.shape_index, test_case.dtype));
        }
        if (test_case.index_mode == "scalar")
        {
            return to_output_bundle(cusignal::cpu::waveforms::unit_impulse(
                test_case.shape, test_case.scalar_index, test_case.dtype));
        }
        return to_output_bundle(cusignal::cpu::waveforms::unit_impulse(test_case.shape, test_case.dtype));
    }

    ZxGpuUnitImpulseResult run_gpu(const UnitImpulseCase &test_case)
    {
        if (!test_case.is_nd)
        {
            if (test_case.index_mode == "mid")
            {
                return cusignal::zx_gpu_backend::waveforms::unit_impulse(
                    test_case.size, std::string("mid"), test_case.dtype);
            }
            if (test_case.index_mode == "scalar")
            {
                return cusignal::zx_gpu_backend::waveforms::unit_impulse(
                    test_case.size, test_case.scalar_index, test_case.dtype);
            }
            return cusignal::zx_gpu_backend::waveforms::unit_impulse(
                test_case.size, 0, test_case.dtype);
        }

        if (test_case.index_mode == "mid")
        {
            return cusignal::zx_gpu_backend::waveforms::unit_impulse(
                test_case.shape, "mid", test_case.dtype);
        }
        if (test_case.index_mode == "shape")
        {
            return cusignal::zx_gpu_backend::waveforms::unit_impulse(
                test_case.shape, test_case.shape_index, test_case.dtype);
        }
        if (test_case.index_mode == "scalar")
        {
            return cusignal::zx_gpu_backend::waveforms::unit_impulse(
                test_case.shape, test_case.scalar_index, test_case.dtype);
        }
        return cusignal::zx_gpu_backend::waveforms::unit_impulse(test_case.shape, test_case.dtype);
    }

    TimingStats benchmark_kernel(const ChirpCase &test_case, const CliOptions &options)
    {
        if (test_case.t.empty())
        {
            return {};
        }

        DeviceBuffer<float> device_t(test_case.t.size());
        device_t.copy_from_host(test_case.t.data(), test_case.t.size(), "cudaMemcpy chirp kernel input");
        DeviceBuffer<float> device_output(test_case.type == "complex" ? 0 : test_case.t.size());
        DeviceBuffer<float2> device_complex(test_case.type == "complex" ? test_case.t.size() : 0);
        const float phi = cusignal::waveforms_detail::degrees_to_radians(test_case.phi);
        const float linear_beta = (test_case.f1 - test_case.f0) / test_case.t1;
        const int blocks = block_count(test_case.t.size());

        return benchmark_gpu_kernel_latency(options, [&]() {
            const std::string method = cusignal::waveforms_detail::validate_chirp_method(test_case.method);
            if (test_case.type == "complex")
            {
                chirp_linear_complex_kernel<<<blocks, kThreadsPerBlock>>>(
                    device_t.get(),
                    test_case.t.size(),
                    test_case.f0,
                    linear_beta,
                    phi,
                    device_complex.get());
                return;
            }
            if (cusignal::waveforms_detail::is_linear_method(method))
            {
                chirp_linear_real_kernel<<<blocks, kThreadsPerBlock>>>(
                    device_t.get(),
                    test_case.t.size(),
                    test_case.f0,
                    linear_beta,
                    phi,
                    device_output.get());
            }
            else if (cusignal::waveforms_detail::is_quadratic_method(method))
            {
                chirp_quadratic_kernel<<<blocks, kThreadsPerBlock>>>(
                    device_t.get(),
                    test_case.t.size(),
                    test_case.f0,
                    test_case.t1,
                    test_case.f1,
                    phi,
                    test_case.vertex_zero,
                    device_output.get());
            }
            else if (cusignal::waveforms_detail::is_logarithmic_method(method))
            {
                chirp_logarithmic_kernel<<<blocks, kThreadsPerBlock>>>(
                    device_t.get(),
                    test_case.t.size(),
                    test_case.f0,
                    test_case.t1,
                    test_case.f1,
                    phi,
                    device_output.get());
            }
            else
            {
                chirp_hyperbolic_kernel<<<blocks, kThreadsPerBlock>>>(
                    device_t.get(),
                    test_case.t.size(),
                    test_case.f0,
                    test_case.t1,
                    test_case.f1,
                    phi,
                    device_output.get());
            }
        });
    }

    TimingStats benchmark_kernel(const GausspulseCase &test_case, const CliOptions &options)
    {
        if (test_case.t.empty())
        {
            return {};
        }
        DeviceBuffer<float> device_t(test_case.t.size());
        device_t.copy_from_host(
            test_case.t.data(), test_case.t.size(), "cudaMemcpy gausspulse kernel input");
        DeviceBuffer<float> signal(test_case.t.size());
        DeviceBuffer<float> quadrature(test_case.retquad ? test_case.t.size() : 0);
        DeviceBuffer<float> envelope(test_case.retenv ? test_case.t.size() : 0);
        const float a =
            cusignal::waveforms_detail::compute_gausspulse_a(test_case.fc, test_case.bw, test_case.bwr);

        return benchmark_gpu_kernel_latency(options, [&]() {
            if (test_case.retquad && test_case.retenv)
            {
                gausspulse_kernel<true, true><<<block_count(test_case.t.size()), kThreadsPerBlock>>>(
                    device_t.get(), test_case.t.size(), a, test_case.fc,
                    signal.get(), quadrature.get(), envelope.get());
            }
            else if (test_case.retquad)
            {
                gausspulse_kernel<true, false><<<block_count(test_case.t.size()), kThreadsPerBlock>>>(
                    device_t.get(), test_case.t.size(), a, test_case.fc,
                    signal.get(), quadrature.get(), nullptr);
            }
            else if (test_case.retenv)
            {
                gausspulse_kernel<false, true><<<block_count(test_case.t.size()), kThreadsPerBlock>>>(
                    device_t.get(), test_case.t.size(), a, test_case.fc,
                    signal.get(), nullptr, envelope.get());
            }
            else
            {
                gausspulse_kernel<false, false><<<block_count(test_case.t.size()), kThreadsPerBlock>>>(
                    device_t.get(), test_case.t.size(), a, test_case.fc,
                    signal.get(), nullptr, nullptr);
            }
        });
    }

    TimingStats benchmark_kernel(const SawtoothCase &test_case, const CliOptions &options)
    {
        if (test_case.t.empty())
        {
            return {};
        }
        DeviceBuffer<float> device_t(test_case.t.size());
        device_t.copy_from_host(
            test_case.t.data(), test_case.t.size(), "cudaMemcpy sawtooth kernel input");
        DeviceBuffer<float> output(test_case.t.size());
        DeviceBuffer<float> width(test_case.width_is_vector ? test_case.t.size() : 0);
        if (test_case.width_is_vector)
        {
            width.copy_from_host(
                test_case.width_values.data(),
                test_case.width_values.size(),
                "cudaMemcpy sawtooth kernel width");
        }

        return benchmark_gpu_kernel_latency(options, [&]() {
            if (test_case.width_is_vector)
            {
                sawtooth_vector_kernel<<<block_count(test_case.t.size()), kThreadsPerBlock>>>(
                    device_t.get(), width.get(), test_case.t.size(), output.get());
            }
            else
            {
                sawtooth_scalar_kernel<<<block_count(test_case.t.size()), kThreadsPerBlock>>>(
                    device_t.get(), test_case.t.size(), test_case.width_scalar, output.get());
            }
        });
    }

    TimingStats benchmark_kernel(const SquareCase &test_case, const CliOptions &options)
    {
        if (test_case.t.empty())
        {
            return {};
        }
        DeviceBuffer<float> device_t(test_case.t.size());
        device_t.copy_from_host(
            test_case.t.data(), test_case.t.size(), "cudaMemcpy square kernel input");
        DeviceBuffer<float> output(test_case.t.size());
        DeviceBuffer<float> duty(test_case.duty_is_vector ? test_case.t.size() : 0);
        if (test_case.duty_is_vector)
        {
            duty.copy_from_host(
                test_case.duty_values.data(),
                test_case.duty_values.size(),
                "cudaMemcpy square kernel duty");
        }

        return benchmark_gpu_kernel_latency(options, [&]() {
            if (test_case.duty_is_vector)
            {
                square_vector_kernel<<<block_count(test_case.t.size()), kThreadsPerBlock>>>(
                    device_t.get(), duty.get(), test_case.t.size(), output.get());
            }
            else
            {
                square_scalar_kernel<<<block_count(test_case.t.size()), kThreadsPerBlock>>>(
                    device_t.get(), test_case.t.size(), test_case.duty_scalar, output.get());
            }
        });
    }

    TimingStats benchmark_kernel(const UnitImpulseCase &test_case, const CliOptions &options)
    {
        const std::size_t size =
            test_case.is_nd ? cusignal::core::shape_product(test_case.shape) : test_case.size;
        if (size == 0)
        {
            return {};
        }

        DeviceBuffer<float> output(size);
        throw_on_zx_gpu_error(cudaMemset(output.get(), 0, size * sizeof(float)), "cudaMemset impulse kernel");
        std::size_t flat_index = 0;
        if (!test_case.is_nd)
        {
            if (test_case.index_mode == "mid")
            {
                flat_index = test_case.size / 2;
            }
            else if (test_case.index_mode == "scalar")
            {
                flat_index = test_case.scalar_index;
            }
        }
        else
        {
            if (test_case.index_mode == "mid")
            {
                flat_index = cusignal::waveforms_detail::flatten_index(
                    test_case.shape, cusignal::waveforms_detail::mid_index(test_case.shape));
            }
            else if (test_case.index_mode == "scalar")
            {
                flat_index = cusignal::waveforms_detail::flatten_index(
                    test_case.shape,
                    cusignal::waveforms_detail::repeated_index(test_case.shape, test_case.scalar_index));
            }
            else if (test_case.index_mode == "shape")
            {
                flat_index =
                    cusignal::waveforms_detail::flatten_index(test_case.shape, test_case.shape_index);
            }
        }

        return benchmark_gpu_kernel_latency(options, [&]() {
            set_impulse_kernel<<<1, 1>>>(output.get(), flat_index);
        });
    }

    void verify_chirp_exceptions()
    {
        const RealSignal t{0.0, 0.25};
        bool threw = false;
        try
        {
            (void)cusignal::cpu::waveforms::chirp(t, 1.0, 1.0, 2.0, "linear", 0.0, true, "bad");
        }
        catch (const std::invalid_argument &)
        {
            threw = true;
        }
        assert_condition(threw, "cpu chirp should reject invalid type");

        threw = false;
        try
        {
            (void)cusignal::zx_gpu_backend::waveforms::chirp(
                t, 0.0, 1.0, 2.0, "logarithmic", 0.0, true, "real");
        }
        catch (const std::invalid_argument &)
        {
            threw = true;
        }
        assert_condition(threw, "gpu chirp should reject invalid logarithmic frequencies");
    }

    void verify_gausspulse_exceptions()
    {
        const RealSignal t{0.0, 0.25};
        bool threw = false;
        try
        {
            (void)cusignal::cpu::waveforms::gausspulse(t, -1.0);
        }
        catch (const std::invalid_argument &)
        {
            threw = true;
        }
        assert_condition(threw, "cpu gausspulse should reject negative fc");

        threw = false;
        try
        {
            (void)cusignal::zx_gpu_backend::waveforms::gausspulse("bad");
        }
        catch (const std::invalid_argument &)
        {
            threw = true;
        }
        assert_condition(threw, "gpu gausspulse cutoff string should validate");
    }

    void verify_sawtooth_exceptions()
    {
        const RealSignal t{0.0, 0.25};
        bool threw = false;
        try
        {
            (void)cusignal::cpu::waveforms::sawtooth(t, 1.5);
        }
        catch (const std::invalid_argument &)
        {
            threw = true;
        }
        assert_condition(threw, "cpu sawtooth should reject width > 1");

        threw = false;
        try
        {
            (void)cusignal::zx_gpu_backend::waveforms::sawtooth(t, RealSignal{0.5});
        }
        catch (const std::invalid_argument &)
        {
            threw = true;
        }
        assert_condition(threw, "gpu sawtooth should validate width vector length");
    }

    void verify_square_exceptions()
    {
        const RealSignal t{0.0, 0.25};
        bool threw = false;
        try
        {
            (void)cusignal::cpu::waveforms::square(t, -0.1);
        }
        catch (const std::invalid_argument &)
        {
            threw = true;
        }
        assert_condition(threw, "cpu square should reject duty < 0");

        threw = false;
        try
        {
            (void)cusignal::zx_gpu_backend::waveforms::square(t, RealSignal{0.5});
        }
        catch (const std::invalid_argument &)
        {
            threw = true;
        }
        assert_condition(threw, "gpu square should validate duty vector length");
    }

    void verify_unit_impulse_exceptions()
    {
        bool threw = false;
        try
        {
            (void)cusignal::cpu::waveforms::unit_impulse(4, 7);
        }
        catch (const std::out_of_range &)
        {
            threw = true;
        }
        assert_condition(threw, "cpu unit_impulse should reject out-of-range index");

        threw = false;
        try
        {
            (void)cusignal::zx_gpu_backend::waveforms::unit_impulse(Shape{2, 3}, Shape{2, 0});
        }
        catch (const std::out_of_range &)
        {
            threw = true;
        }
        assert_condition(threw, "gpu unit_impulse should reject nd out-of-range index");
    }

    template <typename CaseType, typename GpuRunner>
    auto make_gpu_perf_runner(const CaseType &test_case, GpuRunner gpu_runner)
    {
        if constexpr (std::is_same_v<CaseType, ChirpCase>)
        {
            return [test_case, device_t = ZxGpuRealSignal::from_host(test_case.t)]() mutable {
                return run_gpu(test_case, device_t);
            };
        }
        else if constexpr (std::is_same_v<CaseType, GausspulseCase>)
        {
            return [test_case, device_t = ZxGpuRealSignal::from_host(test_case.t)]() mutable {
                return run_gpu(test_case, device_t);
            };
        }
        else if constexpr (std::is_same_v<CaseType, SawtoothCase>)
        {
            return [
                test_case,
                device_t = ZxGpuRealSignal::from_host(test_case.t),
                device_width = test_case.width_is_vector
                                   ? ZxGpuRealSignal::from_host(test_case.width_values)
                                   : ZxGpuRealSignal{}]() mutable {
                return run_gpu(
                    test_case,
                    device_t,
                    test_case.width_is_vector ? &device_width : nullptr);
            };
        }
        else if constexpr (std::is_same_v<CaseType, SquareCase>)
        {
            return [
                test_case,
                device_t = ZxGpuRealSignal::from_host(test_case.t),
                device_duty = test_case.duty_is_vector
                                  ? ZxGpuRealSignal::from_host(test_case.duty_values)
                                  : ZxGpuRealSignal{}]() mutable {
                return run_gpu(
                    test_case,
                    device_t,
                    test_case.duty_is_vector ? &device_duty : nullptr);
            };
        }
        else
        {
            return [&test_case, gpu_runner]() {
                return gpu_runner(test_case);
            };
        }
    }

    template <typename CaseType>
    std::size_t infer_perf_samples(const CaseType &)
    {
        return 0;
    }

    std::size_t infer_perf_samples(const ChirpCase &test_case)
    {
        return test_case.t.size();
    }

    std::size_t infer_perf_samples(const GausspulseCase &test_case)
    {
        return test_case.t.size();
    }

    std::size_t infer_perf_samples(const SawtoothCase &test_case)
    {
        return test_case.t.size();
    }

    std::size_t infer_perf_samples(const SquareCase &test_case)
    {
        return test_case.t.size();
    }

    std::size_t infer_perf_samples(const UnitImpulseCase &test_case)
    {
        if (!test_case.is_nd)
        {
            return test_case.size;
        }
        std::size_t total = 1;
        for (const std::size_t dim : test_case.shape)
        {
            total *= dim;
        }
        return total;
    }

    template <typename CaseType, typename CpuRunner, typename GpuRunner, typename ExpectedLoader, typename KernelBench, typename InputWriter>
    int execute_operator(
        const std::string &op,
        const CliOptions &options,
        const std::vector<CaseType> &accuracy_cases,
        const std::vector<CaseType> &perf_cases,
        CpuRunner cpu_runner,
        GpuRunner gpu_runner,
        ExpectedLoader expected_loader,
        KernelBench kernel_bench,
        InputWriter input_writer,
        const std::function<void()> &exception_checks)
    {
        std::vector<CaseReport> reports;

        if (include_accuracy_cases(options))
        {
            for (const CaseType &test_case : accuracy_cases)
            {
                CaseReport report;
                report.case_id = test_case.id;
                report.category = "accuracy";

                const auto cpu_output =
                    apply_dtype_quantization(to_output_bundle(cpu_runner(test_case)), test_case.dtype);
                const auto gpu_output =
                    apply_dtype_quantization(to_output_bundle(gpu_runner(test_case)), test_case.dtype);
                report.samples = cpu_output.channels.empty() ? 0 : cpu_output.channels.front().values.size();
                report.cpu_gpu_error =
                    compare_output_bundles(gpu_output, cpu_output, test_case.atol, test_case.rtol);
                report.pass = report.cpu_gpu_error.exact_match;

                const OutputBundle expected =
                    apply_dtype_quantization(expected_loader(test_case), test_case.dtype);
                if (!expected.channels.empty())
                {
                    report.cpu_reference_error =
                        compare_output_bundles(cpu_output, expected, test_case.atol, test_case.rtol);
                    report.gpu_reference_error = compare_output_bundles(
                        gpu_output, expected, test_case.atol, test_case.rtol);
                    report.pass = report.pass && report.cpu_reference_error->exact_match &&
                                  report.gpu_reference_error->exact_match;
                }

                if (options.verbose)
                {
                    std::cout << op << "/" << report.case_id
                              << " max_abs=" << format_float(report.cpu_gpu_error.max_abs_error)
                              << " pass=" << (report.pass ? "true" : "false") << '\n';
                }
                reports.push_back(std::move(report));
            }
        }

        if (include_perf_cases(options))
        {
            for (const CaseType &test_case : perf_cases)
            {
                CaseReport report;
                report.case_id = test_case.id;
                report.category = "perf";
                auto gpu_perf_runner = make_gpu_perf_runner(test_case, gpu_runner);
                OutputBundle gpu_output;
                if (!options.gpu_only_perf)
                {
                    gpu_output = to_output_bundle(gpu_perf_runner());
                    report.samples = gpu_output.channels.empty() ? 0 : gpu_output.channels.front().values.size();
                }
                else
                {
                    report.samples = infer_perf_samples(test_case);
                }
                report.pass = true;
                if (!options.gpu_only_perf)
                {
                    const auto cpu_output = to_output_bundle(cpu_runner(test_case));
                    report.cpu_gpu_error =
                        compare_output_bundles(gpu_output, cpu_output, test_case.atol, test_case.rtol);
                    report.pass = report.cpu_gpu_error.exact_match;
                    report.cpu_perf = benchmark_host_latency(options, [&]() { (void)cpu_runner(test_case); });
                }
                report.gpu_e2e_perf =
                    benchmark_host_latency(options, [&]() {
                        (void)gpu_perf_runner();
                        cusignal::core::throw_on_zx_gpu_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize gpu e2e");
                    });
                report.gpu_kernel_perf = kernel_bench(test_case, options);

                if (options.emit_report)
                {
                    if (!options.gpu_only_perf)
                    {
                        const fs::path generated = generated_root(op);
                        input_writer(test_case, generated / "input", &report.artifacts);
                        const auto cpu_output = to_output_bundle(cpu_runner(test_case));
                        write_sample_bundle(generated / "output_samples", test_case.id, "cpu", cpu_output, &report.artifacts);
                        write_sample_bundle(
                            generated / "output_samples",
                            test_case.id,
                            "gpu",
                            gpu_output,
                            &report.artifacts);
                    }
                }

                if (options.verbose)
                {
                    std::cout << op << "/" << report.case_id
                              << " cpu_median="
                              << (report.cpu_perf.has_value() ? format_fixed(report.cpu_perf->median_ms) : "n/a")
                              << " gpu_median=" << format_fixed(report.gpu_e2e_perf->median_ms)
                              << '\n';
                }
                reports.push_back(std::move(report));
            }
        }

        exception_checks();

        const OperatorSummary summary = summarize_cases(reports);
        if (options.emit_report)
        {
            write_operator_report(op, options, reports);
            update_module_reports();
        }
        print_operator_terminal_summary(op, summary);
        return summary.pass ? 0 : 1;
    }

    void write_input_artifact(const ChirpCase &test_case, const fs::path &dir, std::vector<Artifact> *artifacts)
    {
        write_input_csv(dir / (test_case.id + "__t.csv"), test_case.t, artifacts);
    }

    void write_input_artifact(const GausspulseCase &test_case, const fs::path &dir, std::vector<Artifact> *artifacts)
    {
        write_input_csv(dir / (test_case.id + "__t.csv"), test_case.t, artifacts);
    }

    void write_input_artifact(const SawtoothCase &test_case, const fs::path &dir, std::vector<Artifact> *artifacts)
    {
        write_input_csv(dir / (test_case.id + "__t.csv"), test_case.t, artifacts);
        if (test_case.width_is_vector)
        {
            write_input_csv(dir / (test_case.id + "__width.csv"), test_case.width_values, artifacts);
        }
    }

    void write_input_artifact(const SquareCase &test_case, const fs::path &dir, std::vector<Artifact> *artifacts)
    {
        write_input_csv(dir / (test_case.id + "__t.csv"), test_case.t, artifacts);
        if (test_case.duty_is_vector)
        {
            write_input_csv(dir / (test_case.id + "__duty.csv"), test_case.duty_values, artifacts);
        }
    }

    void write_input_artifact(const UnitImpulseCase &, const fs::path &, std::vector<Artifact> *)
    {
    }
} // namespace

int run_chirp_tests(int argc, char **argv)
{
    try
    {
        const CliOptions options = parse_cli(argc, argv);
        return execute_operator(
            "chirp",
            options,
            load_chirp_cases(reference_root("chirp") / "manifest.json", "accuracy"),
            limit_live_perf_cases(load_chirp_cases(generated_root("chirp") / "manifest.json", "perf")),
            [](const ChirpCase &test_case) { return run_cpu(test_case); },
            [](const ChirpCase &test_case) { return run_gpu(test_case); },
            [](const ChirpCase &test_case) { return load_expected_chirp(test_case); },
            [](const ChirpCase &test_case, const CliOptions &opts) { return benchmark_kernel(test_case, opts); },
            [](const ChirpCase &test_case, const fs::path &dir, std::vector<Artifact> *artifacts) {
                write_input_artifact(test_case, dir, artifacts);
            },
            []() { verify_chirp_exceptions(); });
    }
    catch (const std::exception &error)
    {
        std::cerr << "waveforms/chirp failed: " << error.what() << '\n';
        return 1;
    }
}

int run_gausspulse_tests(int argc, char **argv)
{
    try
    {
        const CliOptions options = parse_cli(argc, argv);
        // 额外的标量 cutoff 参考值校验。
        const float cutoff_cpu = cusignal::cpu::waveforms::gausspulse("cutoff", 5.0, 0.5, -6.0, -60.0);
        const float cutoff_gpu =
            cusignal::zx_gpu_backend::waveforms::gausspulse("cutoff", 5.0, 0.5, -6.0, -60.0);
        assert_condition(
            std::fabs(cutoff_cpu - 0.5562590089628512f) < 1.0e-6f,
            "cpu gausspulse cutoff mismatch");
        assert_condition(
            std::fabs(cutoff_gpu - cutoff_cpu) < 1.0e-6f,
            "gpu gausspulse cutoff mismatch");

        return execute_operator(
            "gausspulse",
            options,
            load_gausspulse_cases(reference_root("gausspulse") / "manifest.json", "accuracy"),
            limit_live_perf_cases(load_gausspulse_cases(generated_root("gausspulse") / "manifest.json", "perf")),
            [](const GausspulseCase &test_case) { return run_cpu(test_case); },
            [](const GausspulseCase &test_case) { return run_gpu(test_case); },
            [](const GausspulseCase &test_case) { return load_expected_gausspulse(test_case); },
            [](const GausspulseCase &test_case, const CliOptions &opts) { return benchmark_kernel(test_case, opts); },
            [](const GausspulseCase &test_case, const fs::path &dir, std::vector<Artifact> *artifacts) {
                write_input_artifact(test_case, dir, artifacts);
            },
            []() { verify_gausspulse_exceptions(); });
    }
    catch (const std::exception &error)
    {
        std::cerr << "waveforms/gausspulse failed: " << error.what() << '\n';
        return 1;
    }
}

int run_sawtooth_tests(int argc, char **argv)
{
    try
    {
        const CliOptions options = parse_cli(argc, argv);
        return execute_operator(
            "sawtooth",
            options,
            load_scalar_wave_cases<SawtoothCase>(
                reference_root("sawtooth") / "manifest.json", "accuracy", "width_file", "width"),
            limit_live_perf_cases(load_scalar_wave_cases<SawtoothCase>(
                generated_root("sawtooth") / "manifest.json", "perf", "width_file", "width")),
            [](const SawtoothCase &test_case) { return run_cpu(test_case); },
            [](const SawtoothCase &test_case) { return run_gpu(test_case); },
            [](const SawtoothCase &test_case) { return load_expected_signal(test_case.expected_signal_file); },
            [](const SawtoothCase &test_case, const CliOptions &opts) { return benchmark_kernel(test_case, opts); },
            [](const SawtoothCase &test_case, const fs::path &dir, std::vector<Artifact> *artifacts) {
                write_input_artifact(test_case, dir, artifacts);
            },
            []() { verify_sawtooth_exceptions(); });
    }
    catch (const std::exception &error)
    {
        std::cerr << "waveforms/sawtooth failed: " << error.what() << '\n';
        return 1;
    }
}

int run_square_tests(int argc, char **argv)
{
    try
    {
        const CliOptions options = parse_cli(argc, argv);
        return execute_operator(
            "square",
            options,
            load_scalar_wave_cases<SquareCase>(
                reference_root("square") / "manifest.json", "accuracy", "duty_file", "duty"),
            limit_live_perf_cases(load_scalar_wave_cases<SquareCase>(
                generated_root("square") / "manifest.json", "perf", "duty_file", "duty")),
            [](const SquareCase &test_case) { return run_cpu(test_case); },
            [](const SquareCase &test_case) { return run_gpu(test_case); },
            [](const SquareCase &test_case) { return load_expected_signal(test_case.expected_signal_file); },
            [](const SquareCase &test_case, const CliOptions &opts) { return benchmark_kernel(test_case, opts); },
            [](const SquareCase &test_case, const fs::path &dir, std::vector<Artifact> *artifacts) {
                write_input_artifact(test_case, dir, artifacts);
            },
            []() { verify_square_exceptions(); });
    }
    catch (const std::exception &error)
    {
        std::cerr << "waveforms/square failed: " << error.what() << '\n';
        return 1;
    }
}

int run_unit_impulse_tests(int argc, char **argv)
{
    try
    {
        const CliOptions options = parse_cli(argc, argv);
        return execute_operator(
            "unit_impulse",
            options,
            load_unit_impulse_cases(reference_root("unit_impulse") / "manifest.json", "accuracy"),
            limit_live_perf_cases(load_unit_impulse_cases(generated_root("unit_impulse") / "manifest.json", "perf")),
            [](const UnitImpulseCase &test_case) { return run_cpu(test_case); },
            [](const UnitImpulseCase &test_case) { return run_gpu(test_case); },
            [](const UnitImpulseCase &test_case) { return load_expected_unit_impulse(test_case); },
            [](const UnitImpulseCase &test_case, const CliOptions &opts) { return benchmark_kernel(test_case, opts); },
            [](const UnitImpulseCase &test_case, const fs::path &dir, std::vector<Artifact> *artifacts) {
                write_input_artifact(test_case, dir, artifacts);
            },
            []() { verify_unit_impulse_exceptions(); });
    }
    catch (const std::exception &error)
    {
        std::cerr << "waveforms/unit_impulse failed: " << error.what() << '\n';
        return 1;
    }
}
