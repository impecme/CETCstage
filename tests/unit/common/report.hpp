#pragma once

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "cusignal/core/types.hpp"
#include "json.hpp"

namespace cusignal_test::report
{
    namespace fs = std::filesystem;

    struct WritePolicy
    {
        bool emit_case_reference_errors = true;
        bool emit_case_notes = true;
    };

    inline std::string read_text_file(const fs::path &path)
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

    inline void write_text_file(const fs::path &path, const std::string &content)
    {
        fs::create_directories(path.parent_path());
        std::ofstream output(path);
        if (!output)
        {
            throw std::runtime_error("failed to write file: " + path.string());
        }
        output << content;
    }

    inline std::string capture_command(const std::string &command)
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

    inline std::string sha256_of_file(const fs::path &path)
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

    inline std::string current_timestamp()
    {
        const auto now = std::chrono::system_clock::now();
        const std::time_t time = std::chrono::system_clock::to_time_t(now);
        std::tm tm {};
#if defined(_WIN32)
        localtime_s(&tm, &time);
#else
        localtime_r(&time, &tm);
#endif
        std::ostringstream stream;
        stream << std::put_time(&tm, "%Y-%m-%d %H:%M:%S");
        return stream.str();
    }

    inline std::string json_escape(const std::string &value)
    {
        std::ostringstream stream;
        for (char ch : value)
        {
            switch (ch)
            {
            case '\\':
                stream << "\\\\";
                break;
            case '"':
                stream << "\\\"";
                break;
            case '\n':
                stream << "\\n";
                break;
            case '\r':
                stream << "\\r";
                break;
            case '\t':
                stream << "\\t";
                break;
            default:
                stream << ch;
                break;
            }
        }
        return stream.str();
    }

    inline std::string format_float(float value)
    {
        std::ostringstream stream;
        stream << std::scientific << std::setprecision(6) << value;
        return stream.str();
    }

    inline std::string format_fixed(float value)
    {
        std::ostringstream stream;
        stream << std::fixed << std::setprecision(3) << value;
        return stream.str();
    }

    inline double bytes_to_mib(std::size_t bytes)
    {
        return static_cast<double>(bytes) / (1024.0 * 1024.0);
    }

    template <typename TimingStatsT>
    inline float median_speedup(
        const std::optional<TimingStatsT> &baseline,
        const std::optional<TimingStatsT> &candidate)
    {
        if (!baseline.has_value() || !candidate.has_value() || candidate->median_ms <= 0.0)
        {
            return 0.0;
        }
        return baseline->median_ms / candidate->median_ms;
    }

    template <typename TimingStatsT>
    inline std::string build_timing_stats_json(
        const TimingStatsT &stats,
        int warmup,
        int repeat,
        int indent)
    {
        const std::string current_indent(static_cast<std::size_t>(indent), ' ');
        const std::string child_indent(static_cast<std::size_t>(indent + 2), ' ');
        std::ostringstream stream;
        stream << "{\n";
        stream << child_indent << "\"warmup\": " << warmup << ",\n";
        stream << child_indent << "\"repeat\": " << repeat << ",\n";
        stream << child_indent << "\"mean_ms\": " << stats.mean_ms << ",\n";
        stream << child_indent << "\"median_ms\": " << stats.median_ms << ",\n";
        stream << child_indent << "\"p95_ms\": " << stats.p95_ms << ",\n";
        stream << child_indent << "\"min_ms\": " << stats.min_ms << ",\n";
        stream << child_indent << "\"max_ms\": " << stats.max_ms << ",\n";
        stream << child_indent << "\"std_ms\": " << stats.std_ms << '\n';
        stream << current_indent << '}';
        return stream.str();
    }

    template <typename ErrorMetricsT>
    inline std::string build_error_json(const ErrorMetricsT &metrics, int indent)
    {
        const std::string current_indent(static_cast<std::size_t>(indent), ' ');
        const std::string child_indent(static_cast<std::size_t>(indent + 2), ' ');
        std::ostringstream stream;
        stream << "{\n";
        stream << child_indent << "\"max_abs_error\": " << metrics.max_abs_error << ",\n";
        stream << child_indent << "\"max_rel_error\": " << metrics.max_rel_error << ",\n";
        stream << child_indent << "\"mixed_error\": " << metrics.mixed_error << ",\n";
        stream << child_indent << "\"rmse\": " << metrics.rmse << ",\n";
        stream << child_indent << "\"l2_error\": " << metrics.l2_error << ",\n";
        stream << child_indent << "\"exact_match\": "
               << (metrics.exact_match ? "true" : "false") << ",\n";
        stream << child_indent << "\"first_mismatch_index\": "
               << metrics.first_mismatch_index << "\n";
        stream << current_indent << '}';
        return stream.str();
    }

    template <typename TimingStatsT>
    inline void append_timing_stats_field(
        std::ostringstream &stream,
        const std::string &key,
        const std::optional<TimingStatsT> &stats,
        int warmup,
        int repeat,
        int indent,
        bool &has_previous_field)
    {
        if (!stats.has_value())
        {
            return;
        }

        if (has_previous_field)
        {
            stream << ",\n";
        }
        stream << std::string(static_cast<std::size_t>(indent), ' ') << '"' << key << "\": "
               << build_timing_stats_json(*stats, warmup, repeat, indent);
        has_previous_field = true;
    }

    inline std::string build_device_storage_cache_stats_json(int indent)
    {
        const auto stats = cusignal::core::device_storage_cache_stats_snapshot();
        const std::string current_indent(static_cast<std::size_t>(indent), ' ');
        const std::string child_indent(static_cast<std::size_t>(indent + 2), ' ');
        std::ostringstream stream;
        stream << "{\n";
        stream << child_indent << "\"cache_enabled\": "
               << (stats.cache_enabled ? "true" : "false") << ",\n";
        stream << child_indent << "\"allocation_calls\": " << stats.allocation_calls << ",\n";
        stream << child_indent << "\"allocation_bytes\": " << stats.allocation_bytes << ",\n";
        stream << child_indent << "\"allocation_mib\": " << bytes_to_mib(stats.allocation_bytes) << ",\n";
        stream << child_indent << "\"cache_hits\": " << stats.cache_hits << ",\n";
        stream << child_indent << "\"cache_misses\": " << stats.cache_misses << ",\n";
        stream << child_indent << "\"recycled_blocks\": " << stats.recycled_blocks << ",\n";
        stream << child_indent << "\"recycled_bytes\": " << stats.recycled_bytes << ",\n";
        stream << child_indent << "\"recycled_mib\": " << bytes_to_mib(stats.recycled_bytes) << ",\n";
        stream << child_indent << "\"evicted_blocks\": " << stats.evicted_blocks << ",\n";
        stream << child_indent << "\"evicted_bytes\": " << stats.evicted_bytes << ",\n";
        stream << child_indent << "\"evicted_mib\": " << bytes_to_mib(stats.evicted_bytes) << ",\n";
        stream << child_indent << "\"freed_blocks\": " << stats.freed_blocks << ",\n";
        stream << child_indent << "\"freed_bytes\": " << stats.freed_bytes << ",\n";
        stream << child_indent << "\"freed_mib\": " << bytes_to_mib(stats.freed_bytes) << ",\n";
        stream << child_indent << "\"cached_blocks\": " << stats.cached_blocks << ",\n";
        stream << child_indent << "\"cached_bytes\": " << stats.cached_bytes << ",\n";
        stream << child_indent << "\"cached_mib\": " << bytes_to_mib(stats.cached_bytes) << ",\n";
        stream << child_indent << "\"peak_cached_bytes\": " << stats.peak_cached_bytes << ",\n";
        stream << child_indent << "\"peak_cached_mib\": "
               << bytes_to_mib(stats.peak_cached_bytes) << ",\n";
        stream << child_indent << "\"max_cached_blocks\": " << stats.max_cached_blocks << ",\n";
        stream << child_indent << "\"max_cached_bytes\": " << stats.max_cached_bytes << ",\n";
        stream << child_indent << "\"max_cached_mib\": " << bytes_to_mib(stats.max_cached_bytes) << ",\n";
        stream << child_indent << "\"max_single_cached_bytes\": "
               << stats.max_single_cached_bytes << ",\n";
        stream << child_indent << "\"max_single_cached_mib\": "
               << bytes_to_mib(stats.max_single_cached_bytes) << '\n';
        stream << current_indent << '}';
        return stream.str();
    }

    inline void append_device_storage_cache_stats_field(
        std::ostringstream &stream,
        int indent,
        bool &has_previous_field)
    {
        if (has_previous_field)
        {
            stream << ",\n";
        }
        stream << std::string(static_cast<std::size_t>(indent), ' ')
               << "\"device_storage_cache\": "
               << build_device_storage_cache_stats_json(indent);
        has_previous_field = true;
    }

    inline const cusignal_test::json::Object &as_object(
        const cusignal_test::json::Value &value)
    {
        if (!value.is_object())
        {
            throw std::runtime_error("expected JSON object");
        }
        return value.as_object();
    }

    inline float get_optional_number(
        const cusignal_test::json::Object &object,
        const std::string &key,
        float default_value = 0.0)
    {
        const auto iter = object.find(key);
        if (iter == object.end())
        {
            return default_value;
        }
        return iter->second.as_number();
    }

    template <typename SummaryT, typename CaseT>
    inline std::string build_summary_markdown(
        const std::string &module,
        const std::string &op,
        const SummaryT &summary,
        const std::vector<CaseT> &cases)
    {
        std::ostringstream stream;
        stream << "# " << module << '/' << op << " Summary\n\n";
        stream << "- generated_at: " << current_timestamp() << "\n";
        stream << "- pass: " << (summary.pass ? "true" : "false") << "\n";
        stream << "- accuracy_cases: " << summary.accuracy_cases << "\n";
        stream << "- perf_cases: " << summary.perf_cases << "\n\n";
        stream << "## Errors\n\n";
        stream << "- gpu_vs_cpu max_abs: " << format_float(summary.cpu_gpu_error.max_abs_error)
               << "\n";
        stream << "- gpu_vs_cpu max_rel: " << format_float(summary.cpu_gpu_error.max_rel_error)
               << "\n";
        stream << "- gpu_vs_cpu rmse: " << format_float(summary.cpu_gpu_error.rmse) << "\n";
        if (summary.reference_error.has_value())
        {
            stream << "- reference max_abs: "
                   << format_float(summary.reference_error->max_abs_error) << "\n";
            stream << "- reference max_rel: "
                   << format_float(summary.reference_error->max_rel_error) << "\n";
        }
        stream << "\n## Performance\n\n";
        if (!summary.cpu_perf.has_value() && !summary.gpu_e2e_perf.has_value() &&
            !summary.gpu_kernel_perf.has_value())
        {
            stream << "- timing: not_run (accuracy-only case set; use perf/full case set for timing)\n";
        }
        if (summary.cpu_perf.has_value())
        {
            stream << "- cpu median_ms: " << format_fixed(summary.cpu_perf->median_ms) << "\n";
            stream << "- cpu mean_ms: " << format_fixed(summary.cpu_perf->mean_ms) << "\n";
            stream << "- cpu p95_ms: " << format_fixed(summary.cpu_perf->p95_ms) << "\n";
        }
        if (summary.gpu_e2e_perf.has_value())
        {
            stream << "- gpu_e2e median_ms: " << format_fixed(summary.gpu_e2e_perf->median_ms)
                   << "\n";
            stream << "- gpu_e2e mean_ms: " << format_fixed(summary.gpu_e2e_perf->mean_ms)
                   << "\n";
            stream << "- gpu_e2e p95_ms: " << format_fixed(summary.gpu_e2e_perf->p95_ms)
                   << "\n";
            stream << "- gpu_e2e speedup: "
                   << format_fixed(median_speedup(summary.cpu_perf, summary.gpu_e2e_perf))
                   << "x\n";
        }
        if (summary.gpu_kernel_perf.has_value())
        {
            stream << "- gpu_kernel median_ms: "
                   << format_fixed(summary.gpu_kernel_perf->median_ms) << "\n";
            stream << "- gpu_kernel speedup: "
                   << format_fixed(median_speedup(summary.cpu_perf, summary.gpu_kernel_perf))
                   << "x\n";
        }
        const auto cache_stats = cusignal::core::device_storage_cache_stats_snapshot();
        stream << "- device_cache allocations: " << cache_stats.allocation_calls
               << " calls, " << format_fixed(static_cast<float>(bytes_to_mib(cache_stats.allocation_bytes)))
               << " MiB\n";
        stream << "- device_cache hits/misses: " << cache_stats.cache_hits
               << "/" << cache_stats.cache_misses << "\n";
        stream << "- device_cache recycled: " << cache_stats.recycled_blocks
               << " blocks, " << format_fixed(static_cast<float>(bytes_to_mib(cache_stats.recycled_bytes)))
               << " MiB\n";
        stream << "\n## Cases\n\n";
        for (const CaseT &report : cases)
        {
            stream << "- " << report.case_id << ": "
                   << (report.pass ? "pass" : "fail")
                   << ", max_abs=" << format_float(report.cpu_gpu_error.max_abs_error) << "\n";
        }
        return stream.str();
    }

    template <typename CaseT, typename OptionsT>
    inline std::string build_cases_csv(
        const std::vector<CaseT> &cases,
        const OptionsT &options)
    {
        std::ostringstream stream;
        stream << "case_id,backend,metric_kind,samples,warmup,repeat,mean_ms,median_ms,p95_ms,min_ms,max_ms,std_ms,max_abs_error,max_rel_error,rmse,l2_error,exact_match\n";
        for (const CaseT &report : cases)
        {
            stream << report.case_id << ",gpu_vs_cpu,error," << report.samples << ",,,"
                   << ",,,,,," << std::setprecision(17) << report.cpu_gpu_error.max_abs_error << ','
                   << report.cpu_gpu_error.max_rel_error << ',' << report.cpu_gpu_error.rmse
                   << ',' << report.cpu_gpu_error.l2_error << ','
                   << (report.cpu_gpu_error.exact_match ? "true" : "false") << '\n';
            if (report.cpu_reference_error.has_value())
            {
                const auto &metrics = *report.cpu_reference_error;
                stream << report.case_id << ",cpu_vs_ref,error," << report.samples << ",,,"
                       << ",,,,,," << metrics.max_abs_error << ',' << metrics.max_rel_error
                       << ',' << metrics.rmse << ',' << metrics.l2_error << ','
                       << (metrics.exact_match ? "true" : "false") << '\n';
            }
            if (report.gpu_reference_error.has_value())
            {
                const auto &metrics = *report.gpu_reference_error;
                stream << report.case_id << ",gpu_vs_ref,error," << report.samples << ",,,"
                       << ",,,,,," << metrics.max_abs_error << ',' << metrics.max_rel_error
                       << ',' << metrics.rmse << ',' << metrics.l2_error << ','
                       << (metrics.exact_match ? "true" : "false") << '\n';
            }
            if (report.cpu_perf.has_value())
            {
                const auto &stats = *report.cpu_perf;
                stream << report.case_id << ",cpu,perf," << report.samples << ','
                       << options.warmup << ',' << options.repeat << ',' << stats.mean_ms << ','
                       << stats.median_ms << ',' << stats.p95_ms << ',' << stats.min_ms << ','
                       << stats.max_ms << ',' << stats.std_ms << ",,,,,\n";
            }
            if (report.gpu_e2e_perf.has_value())
            {
                const auto &stats = *report.gpu_e2e_perf;
                stream << report.case_id << ",gpu_e2e,perf," << report.samples << ','
                       << options.warmup << ',' << options.repeat << ',' << stats.mean_ms << ','
                       << stats.median_ms << ',' << stats.p95_ms << ',' << stats.min_ms << ','
                       << stats.max_ms << ',' << stats.std_ms << ",,,,,\n";
            }
            if (report.gpu_kernel_perf.has_value())
            {
                const auto &stats = *report.gpu_kernel_perf;
                stream << report.case_id << ",gpu_kernel,perf," << report.samples << ','
                       << options.warmup << ',' << options.repeat << ',' << stats.mean_ms << ','
                       << stats.median_ms << ',' << stats.p95_ms << ',' << stats.min_ms << ','
                       << stats.max_ms << ',' << stats.std_ms << ",,,,,\n";
            }
        }
        return stream.str();
    }

    template <typename ArtifactT>
    inline fs::path artifact_absolute_path(const ArtifactT &artifact)
    {
        return artifact.path.is_absolute() ? artifact.path : fs::absolute(artifact.path);
    }

    template <typename ArtifactT>
    inline std::string artifact_sha256(const ArtifactT &artifact)
    {
        if (!artifact.sha256.empty())
        {
            return artifact.sha256;
        }
        return sha256_of_file(artifact_absolute_path(artifact));
    }

    template <typename SummaryT, typename CaseT, typename OptionsT>
    inline std::string build_metrics_json(
        const std::string &module,
        const std::string &op,
        const fs::path &repo_root,
        long cxx_standard,
        int runtime_version,
        const OptionsT &options,
        const SummaryT &summary,
        const std::vector<CaseT> &cases,
        const WritePolicy &policy)
    {
        cudaDeviceProp properties {};
        std::string gpu_name;
        if (cudaGetDeviceProperties(&properties, 0) == cudaSuccess)
        {
            gpu_name = properties.name;
        }

        std::ostringstream stream;
        stream << "{\n";
        stream << "  \"module\": \"" << json_escape(module) << "\",\n";
        stream << "  \"operator\": \"" << json_escape(op) << "\",\n";
        stream << "  \"generated_at\": \"" << json_escape(current_timestamp()) << "\",\n";
        stream << "  \"git_commit\": \""
               << json_escape(capture_command(
                      "git -C '" + repo_root.string() + "' rev-parse HEAD 2>/dev/null"))
               << "\",\n";
        stream << "  \"gpu_name\": \"" << json_escape(gpu_name) << "\",\n";
        stream << "  \"compile_config\": {\n";
        stream << "    \"cxx_standard\": " << cxx_standard << ",\n";
        stream << "    \"runtime_version\": " << runtime_version << "\n";
        stream << "  },\n";
        stream << "  \"summary\": {\n";
        stream << "    \"pass\": " << (summary.pass ? "true" : "false") << ",\n";
        stream << "    \"accuracy_cases\": " << summary.accuracy_cases << ",\n";
        stream << "    \"perf_cases\": " << summary.perf_cases << ",\n";
        stream << "    \"max_abs_error\": " << summary.cpu_gpu_error.max_abs_error << ",\n";
        stream << "    \"max_rel_error\": " << summary.cpu_gpu_error.max_rel_error << ",\n";
        stream << "    \"mixed_error\": " << summary.cpu_gpu_error.mixed_error << ",\n";
        stream << "    \"rmse\": " << summary.cpu_gpu_error.rmse << ",\n";
        stream << "    \"gpu_e2e_speedup\": "
               << median_speedup(summary.cpu_perf, summary.gpu_e2e_perf) << ",\n";
        stream << "    \"gpu_kernel_speedup\": "
               << median_speedup(summary.cpu_perf, summary.gpu_kernel_perf);
        bool has_summary_field = true;
        append_timing_stats_field(
            stream, "cpu_perf", summary.cpu_perf, options.warmup, options.repeat, 4, has_summary_field);
        append_timing_stats_field(stream,
                                  "gpu_e2e_perf",
                                  summary.gpu_e2e_perf,
                                  options.warmup,
                                  options.repeat,
                                  4,
                                  has_summary_field);
        append_timing_stats_field(stream,
                                  "gpu_kernel_perf",
                                  summary.gpu_kernel_perf,
                                  options.warmup,
                                  options.repeat,
                                  4,
                                  has_summary_field);
        append_device_storage_cache_stats_field(stream, 4, has_summary_field);
        stream << "\n";
        stream << "  },\n";
        stream << "  \"cases\": [\n";
        for (std::size_t index = 0; index < cases.size(); ++index)
        {
            const CaseT &report = cases[index];
            stream << "    {\n";
            stream << "      \"case_id\": \"" << json_escape(report.case_id) << "\",\n";
            stream << "      \"category\": \"" << json_escape(report.category) << "\",\n";
            stream << "      \"samples\": " << report.samples << ",\n";
            stream << "      \"pass\": " << (report.pass ? "true" : "false") << ",\n";
            stream << "      \"cpu_gpu_error\": " << build_error_json(report.cpu_gpu_error, 6);
            if (policy.emit_case_reference_errors && report.cpu_reference_error.has_value())
            {
                stream << ",\n      \"cpu_reference_error\": "
                       << build_error_json(*report.cpu_reference_error, 6);
            }
            if (policy.emit_case_reference_errors && report.gpu_reference_error.has_value())
            {
                stream << ",\n      \"gpu_reference_error\": "
                       << build_error_json(*report.gpu_reference_error, 6);
            }
            bool has_case_timing = true;
            append_timing_stats_field(
                stream, "cpu_perf", report.cpu_perf, options.warmup, options.repeat, 6, has_case_timing);
            append_timing_stats_field(stream,
                                      "gpu_e2e_perf",
                                      report.gpu_e2e_perf,
                                      options.warmup,
                                      options.repeat,
                                      6,
                                      has_case_timing);
            append_timing_stats_field(stream,
                                      "gpu_kernel_perf",
                                      report.gpu_kernel_perf,
                                      options.warmup,
                                      options.repeat,
                                      6,
                                      has_case_timing);
            if (policy.emit_case_notes && !report.note.empty())
            {
                stream << ",\n      \"note\": \"" << json_escape(report.note) << "\"";
            }
            stream << ",\n";
            stream << "      \"artifacts\": [\n";
            for (std::size_t artifact_index = 0; artifact_index < report.artifacts.size();
                 ++artifact_index)
            {
                const auto &artifact = report.artifacts[artifact_index];
                const fs::path absolute_path = artifact_absolute_path(artifact);
                stream << "        {\"role\": \"" << json_escape(artifact.role)
                       << "\", \"path\": \"" << json_escape(absolute_path.string())
                       << "\", \"sha256\": \"" << json_escape(artifact_sha256(artifact)) << "\"}";
                if (artifact_index + 1 != report.artifacts.size())
                {
                    stream << ',';
                }
                stream << '\n';
            }
            stream << "      ]\n";
            stream << "    }";
            if (index + 1 != cases.size())
            {
                stream << ',';
            }
            stream << '\n';
        }
        stream << "  ]\n";
        stream << "}\n";
        return stream.str();
    }

    template <typename SummaryT, typename OptionsT>
    inline std::string build_summary_only_metrics_json(
        const std::string &module,
        const std::string &op,
        const fs::path &repo_root,
        long cxx_standard,
        int runtime_version,
        const OptionsT &options,
        const SummaryT &summary)
    {
        cudaDeviceProp properties {};
        std::string gpu_name;
        if (cudaGetDeviceProperties(&properties, 0) == cudaSuccess)
        {
            gpu_name = properties.name;
        }

        std::ostringstream stream;
        stream << "{\n";
        stream << "  \"module\": \"" << json_escape(module) << "\",\n";
        stream << "  \"operator\": \"" << json_escape(op) << "\",\n";
        stream << "  \"generated_at\": \"" << json_escape(current_timestamp()) << "\",\n";
        stream << "  \"git_commit\": \""
               << json_escape(capture_command(
                      "git -C '" + repo_root.string() + "' rev-parse HEAD 2>/dev/null"))
               << "\",\n";
        stream << "  \"gpu_name\": \"" << json_escape(gpu_name) << "\",\n";
        stream << "  \"compile_config\": {\n";
        stream << "    \"cxx_standard\": " << cxx_standard << ",\n";
        stream << "    \"runtime_version\": " << runtime_version << "\n";
        stream << "  },\n";
        stream << "  \"summary\": {\n";
        stream << "    \"pass\": " << (summary.pass ? "true" : "false") << ",\n";
        stream << "    \"accuracy_cases\": " << summary.accuracy_cases << ",\n";
        stream << "    \"perf_cases\": " << summary.perf_cases << ",\n";
        stream << "    \"max_abs_error\": " << summary.cpu_gpu_error.max_abs_error << ",\n";
        stream << "    \"max_rel_error\": " << summary.cpu_gpu_error.max_rel_error << ",\n";
        stream << "    \"mixed_error\": " << summary.cpu_gpu_error.mixed_error << ",\n";
        stream << "    \"rmse\": " << summary.cpu_gpu_error.rmse << ",\n";
        stream << "    \"gpu_e2e_speedup\": "
               << median_speedup(summary.cpu_perf, summary.gpu_e2e_perf) << ",\n";
        stream << "    \"gpu_kernel_speedup\": "
               << median_speedup(summary.cpu_perf, summary.gpu_kernel_perf);
        bool has_summary_field = true;
        append_timing_stats_field(
            stream, "cpu_perf", summary.cpu_perf, options.warmup, options.repeat, 4, has_summary_field);
        append_timing_stats_field(stream,
                                  "gpu_e2e_perf",
                                  summary.gpu_e2e_perf,
                                  options.warmup,
                                  options.repeat,
                                  4,
                                  has_summary_field);
        append_timing_stats_field(stream,
                                  "gpu_kernel_perf",
                                  summary.gpu_kernel_perf,
                                  options.warmup,
                                  options.repeat,
                                  4,
                                  has_summary_field);
        append_device_storage_cache_stats_field(stream, 4, has_summary_field);
        stream << "\n";
        stream << "  },\n";
        stream << "  \"cases\": []\n";
        stream << "}\n";
        return stream.str();
    }

    template <typename SummaryT, typename OptionsT>
    inline void write_summary_only_metrics(
        const std::string &module,
        const std::string &op,
        const fs::path &repo_root,
        const fs::path &operator_report_root,
        long cxx_standard,
        int runtime_version,
        const OptionsT &options,
        const SummaryT &summary)
    {
        const std::string metrics_json =
            build_summary_only_metrics_json(module,
                                            op,
                                            repo_root,
                                            cxx_standard,
                                            runtime_version,
                                            options,
                                            summary);
        write_text_file(operator_report_root / "latest_metrics.json", metrics_json);
    }

    template <typename SummaryT, typename CaseT, typename OptionsT>
    inline void write_operator_report(
        const std::string &module,
        const std::string &op,
        const fs::path &repo_root,
        const fs::path &operator_report_root,
        long cxx_standard,
        int runtime_version,
        const OptionsT &options,
        const SummaryT &summary,
        const std::vector<CaseT> &cases,
        const WritePolicy &policy)
    {
        const std::string summary_markdown =
            build_summary_markdown(module, op, summary, cases);
        const std::string metrics_json =
            build_metrics_json(module,
                               op,
                               repo_root,
                               cxx_standard,
                               runtime_version,
                               options,
                               summary,
                               cases,
                               policy);
        const std::string cases_csv = build_cases_csv(cases, options);

        write_text_file(operator_report_root / "latest_summary.md", summary_markdown);
        write_text_file(operator_report_root / "latest_metrics.json", metrics_json);
        write_text_file(operator_report_root / "latest_cases.csv", cases_csv);
    }

    inline std::string build_timing_stats_json_from_object(
        const cusignal_test::json::Object &object,
        int indent)
    {
        const std::string current_indent(static_cast<std::size_t>(indent), ' ');
        const std::string child_indent(static_cast<std::size_t>(indent + 2), ' ');
        std::ostringstream stream;
        stream << "{\n";
        stream << child_indent << "\"warmup\": " << get_optional_number(object, "warmup")
               << ",\n";
        stream << child_indent << "\"repeat\": " << get_optional_number(object, "repeat")
               << ",\n";
        stream << child_indent << "\"mean_ms\": " << get_optional_number(object, "mean_ms")
               << ",\n";
        stream << child_indent << "\"median_ms\": " << get_optional_number(object, "median_ms")
               << ",\n";
        stream << child_indent << "\"p95_ms\": " << get_optional_number(object, "p95_ms")
               << ",\n";
        stream << child_indent << "\"min_ms\": " << get_optional_number(object, "min_ms")
               << ",\n";
        stream << child_indent << "\"max_ms\": " << get_optional_number(object, "max_ms")
               << ",\n";
        stream << child_indent << "\"std_ms\": " << get_optional_number(object, "std_ms")
               << "\n";
        stream << current_indent << '}';
        return stream.str();
    }

    inline void update_module_reports(const std::string &module, const fs::path &module_root)
    {
        fs::create_directories(module_root);

        const auto is_digit = [](char value) {
            return value >= '0' && value <= '9';
        };
        const auto is_timestamped_operator_report_dir = [&](const std::string &name) {
            constexpr std::size_t kSuffixLength = 16; // _YYYYMMDD_HHMMSS
            if (name.size() <= kSuffixLength)
            {
                return false;
            }
            const std::size_t start = name.size() - kSuffixLength;
            if (name[start] != '_' || name[start + 9] != '_')
            {
                return false;
            }
            for (std::size_t index = 1; index < kSuffixLength; ++index)
            {
                if (index == 9)
                {
                    continue;
                }
                if (!is_digit(name[start + index]))
                {
                    return false;
                }
            }
            return true;
        };

        std::vector<fs::path> operator_dirs;
        for (const auto &entry : fs::directory_iterator(module_root))
        {
            if (!entry.is_directory())
            {
                continue;
            }
            if (is_timestamped_operator_report_dir(entry.path().filename().string()))
            {
                continue;
            }
            operator_dirs.push_back(entry.path());
        }
        std::sort(operator_dirs.begin(), operator_dirs.end());

        std::ostringstream summary_md;
        summary_md << "# " << module << " Summary\n\n";
        summary_md << "- generated_at: " << current_timestamp() << "\n\n";
        summary_md << "## Operators\n\n";

        std::ostringstream json_stream;
        json_stream << "{\n";
        json_stream << "  \"module\": \"" << json_escape(module) << "\",\n";
        json_stream << "  \"generated_at\": \"" << json_escape(current_timestamp()) << "\",\n";
        json_stream << "  \"operators\": [\n";

        std::ostringstream csv_stream;
        constexpr const char *kCanonicalCasesHeader =
            "case_id,backend,metric_kind,samples,warmup,repeat,mean_ms,median_ms,p95_ms,min_ms,max_ms,std_ms,max_abs_error,max_rel_error,rmse,l2_error,exact_match";
        bool wrote_csv_header = false;
        bool first_json = true;

        for (const fs::path &operator_dir : operator_dirs)
        {
            const fs::path metrics_path = operator_dir / "latest_metrics.json";
            const fs::path cases_path = operator_dir / "latest_cases.csv";
            if (!fs::exists(metrics_path))
            {
                continue;
            }

            try
            {
                const auto json_value = cusignal_test::json::parse(read_text_file(metrics_path));
                const auto &root = as_object(json_value);
                const auto &summary = as_object(root.at("summary"));
                const std::string op_name = operator_dir.filename().string();
                float max_abs_error = 0.0;
                float max_rel_error = 0.0;
                if (const auto iter = summary.find("max_abs_error"); iter != summary.end())
                {
                    max_abs_error = iter->second.as_number();
                    max_rel_error = summary.at("max_rel_error").as_number();
                }
                else if (const auto iter = summary.find("cpu_gpu_error");
                         iter != summary.end())
                {
                    const auto &cpu_gpu_error = as_object(iter->second);
                    max_abs_error = get_optional_number(cpu_gpu_error, "max_abs_error");
                    max_rel_error = get_optional_number(cpu_gpu_error, "max_rel_error");
                }

                summary_md << "- " << op_name << ": "
                           << (summary.at("pass").as_bool() ? "PASS" : "FAIL")
                           << ", max_abs=" << format_float(max_abs_error)
                           << ", max_rel=" << format_float(max_rel_error) << "\n";

                if (!first_json)
                {
                    json_stream << ",\n";
                }
                first_json = false;
                json_stream << "    {\n";
                json_stream << "      \"operator\": \"" << json_escape(op_name) << "\",\n";
                json_stream << "      \"pass\": "
                            << (summary.at("pass").as_bool() ? "true" : "false") << ",\n";
                json_stream << "      \"max_abs_error\": " << max_abs_error << ",\n";
                json_stream << "      \"max_rel_error\": " << max_rel_error << ",\n";
                json_stream << "      \"gpu_e2e_speedup\": "
                            << get_optional_number(summary, "gpu_e2e_speedup") << ",\n";
                json_stream << "      \"gpu_kernel_speedup\": "
                            << get_optional_number(summary, "gpu_kernel_speedup");

                for (const std::string key : {"cpu_perf", "gpu_e2e_perf", "gpu_kernel_perf"})
                {
                    const auto iter = summary.find(key);
                    if (iter == summary.end())
                    {
                        continue;
                    }
                    json_stream << ",\n      \"" << key << "\": "
                                << build_timing_stats_json_from_object(
                                       as_object(iter->second), 6);
                }
                json_stream << "\n    }";

                if (fs::exists(cases_path))
                {
                    std::istringstream input(read_text_file(cases_path));
                    std::string line;
                    bool first_line = true;
                    while (std::getline(input, line))
                    {
                        if (line.empty())
                        {
                            continue;
                        }
                        if (first_line)
                        {
                            if (line != kCanonicalCasesHeader)
                            {
                                break;
                            }
                            if (!wrote_csv_header)
                            {
                                csv_stream << line << '\n';
                                wrote_csv_header = true;
                            }
                            first_line = false;
                            continue;
                        }
                        csv_stream << line << '\n';
                    }
                }
            }
            catch (const std::exception &)
            {
                continue;
            }
        }

        if (!wrote_csv_header)
        {
            csv_stream << kCanonicalCasesHeader << "\n";
        }

        json_stream << "\n  ]\n";
        json_stream << "}\n";

        write_text_file(module_root / "latest_summary.md", summary_md.str());
        write_text_file(module_root / "latest_metrics.json", json_stream.str());
        write_text_file(module_root / "latest_cases.csv", csv_stream.str());
    }
} // namespace cusignal_test::report
