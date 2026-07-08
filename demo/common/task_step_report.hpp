#pragma once

#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace cusignal_demo::report
{
    struct ErrorMetrics
    {
        float mixed_error = 0.0f;
        float max_abs = 0.0f;
        float max_rel = 0.0f;
        float rmse = 0.0f;
        float real_max_abs = std::numeric_limits<float>::quiet_NaN();
        float imag_max_abs = std::numeric_limits<float>::quiet_NaN();
    };

    struct StageTiming
    {
        std::string name;
        float cpu_ms = 0.0f;
        float gpu_ms = 0.0f;
    };

    struct StepMetric
    {
        std::string step;
        std::string operator_name;
        std::string input_shape;
        std::string output_shape;
        std::string input_dtype;
        std::string output_dtype;
        float cpu_ms = 0.0f;
        float gpu_e2e_ms = 0.0f;
        float gpu_kernel_ms = std::numeric_limits<float>::quiet_NaN();
        ErrorMetrics error;
        bool error_available = false;
        bool complex_error = false;
        bool pass = false;
        std::string note;
    };

    inline std::string json_escape(const std::string &value)
    {
        std::string output;
        for (const char character : value)
        {
            if (character == '\\' || character == '"')
                output.push_back('\\');
            output.push_back(character);
        }
        return output;
    }

    inline std::string csv_escape(const std::string &value)
    {
        bool needs_quote = false;
        for (const char character : value)
        {
            if (character == ',' || character == '"' || character == '\n' || character == '\r')
            {
                needs_quote = true;
                break;
            }
        }
        if (!needs_quote)
        {
            return value;
        }

        std::string output;
        output.reserve(value.size() + 2);
        output.push_back('"');
        for (const char character : value)
        {
            if (character == '"')
            {
                output.push_back('"');
            }
            output.push_back(character);
        }
        output.push_back('"');
        return output;
    }

    inline void write_optional(std::ostream &output, float value)
    {
        if (std::isfinite(value))
            output << value;
        else
            output << "null";
    }

    inline float speedup(float cpu_ms, float gpu_ms)
    {
        return gpu_ms > 0.0f ? cpu_ms / gpu_ms : std::numeric_limits<float>::quiet_NaN();
    }

    inline void write_step_metrics(
        const std::filesystem::path &report_root,
        const std::string &task,
        const std::vector<StepMetric> &steps)
    {
        namespace fs = std::filesystem;
        fs::create_directories(report_root);

        std::ofstream csv(report_root / "latest_step_metrics.csv");
        if (!csv)
            throw std::runtime_error("failed to write task step CSV");
        csv << "task,step,operator,input_shape,output_shape,input_dtype,output_dtype,"
               "cpu_ms,gpu_e2e_ms,gpu_kernel_ms,gpu_e2e_speedup,gpu_kernel_speedup,"
               "max_abs,max_rel,rmse,mixed_error,real_max_abs,imag_max_abs,error_available,pass,note\n";
        csv << std::fixed << std::setprecision(9);
        for (const auto &step : steps)
        {
            csv << csv_escape(task) << ',' << csv_escape(step.step) << ','
                << csv_escape(step.operator_name) << ','
                << csv_escape(step.input_shape) << ',' << csv_escape(step.output_shape) << ','
                << csv_escape(step.input_dtype) << ',' << csv_escape(step.output_dtype) << ','
                << step.cpu_ms << ',' << step.gpu_e2e_ms << ',';
            if (std::isfinite(step.gpu_kernel_ms))
                csv << step.gpu_kernel_ms;
            csv << ',' << speedup(step.cpu_ms, step.gpu_e2e_ms) << ',';
            if (std::isfinite(step.gpu_kernel_ms))
                csv << speedup(step.cpu_ms, step.gpu_kernel_ms);
            csv << ',';
            if (step.error_available)
            {
                csv << step.error.max_abs << ',' << step.error.max_rel << ',' << step.error.rmse << ','
                    << step.error.mixed_error << ',';
                if (step.complex_error)
                    csv << step.error.real_max_abs << ',' << step.error.imag_max_abs;
                else
                    csv << ',';
            }
            else
            {
                csv << ",,,,,";
            }
            csv << ',' << (step.error_available ? "true" : "false") << ','
                << (step.pass ? "true" : "false") << ',' << csv_escape(step.note) << '\n';
        }

        std::ofstream json(report_root / "latest_step_metrics.json");
        if (!json)
            throw std::runtime_error("failed to write task step JSON");
        json << std::setprecision(9) << "{\n  \"task\": \"" << json_escape(task)
             << "\",\n  \"schema_version\": 2,\n  \"steps\": [\n";
        for (std::size_t index = 0; index < steps.size(); ++index)
        {
            const auto &step = steps[index];
            json << "    {\"step\": \"" << json_escape(step.step) << "\", \"operator\": \""
                 << json_escape(step.operator_name) << "\", \"input_shape\": \""
                 << json_escape(step.input_shape) << "\", \"output_shape\": \""
                 << json_escape(step.output_shape) << "\", \"input_dtype\": \""
                 << json_escape(step.input_dtype) << "\", \"output_dtype\": \""
                 << json_escape(step.output_dtype) << "\", \"cpu_ms\": " << step.cpu_ms
                 << ", \"gpu_e2e_ms\": " << step.gpu_e2e_ms << ", \"gpu_kernel_ms\": ";
            write_optional(json, step.gpu_kernel_ms);
            json << ", \"gpu_e2e_speedup\": ";
            write_optional(json, speedup(step.cpu_ms, step.gpu_e2e_ms));
            json << ", \"gpu_kernel_speedup\": ";
            write_optional(json, speedup(step.cpu_ms, step.gpu_kernel_ms));
            json << ", \"error_available\": " << (step.error_available ? "true" : "false")
                 << ", \"error\": ";
            if (step.error_available)
            {
                json << "{\"max_abs\": " << step.error.max_abs << ", \"max_rel\": "
                     << step.error.max_rel << ", \"rmse\": " << step.error.rmse
                     << ", \"mixed_error\": " << step.error.mixed_error
                     << ", \"real_max_abs\": ";
                write_optional(json, step.error.real_max_abs);
                json << ", \"imag_max_abs\": ";
                write_optional(json, step.error.imag_max_abs);
                json << '}';
            }
            else
            {
                json << "null";
            }
            json << ", \"pass\": " << (step.pass ? "true" : "false") << ", \"note\": \""
                 << json_escape(step.note) << "\"}" << (index + 1 == steps.size() ? "\n" : ",\n");
        }
        json << "  ]\n}\n";

        std::ofstream markdown(report_root / "latest_step_metrics.md");
        if (!markdown)
            throw std::runtime_error("failed to write task step Markdown");
        markdown << "# " << task << " Step Metrics\n\n"
                 << "| step | operator | CPU ms | GPU E2E ms | GPU kernel ms | mixed error | pass |\n"
                 << "| --- | --- | ---: | ---: | ---: | ---: | --- |\n";
        for (const auto &step : steps)
        {
            markdown << "| " << step.step << " | " << step.operator_name << " | " << step.cpu_ms
                     << " | " << step.gpu_e2e_ms << " | ";
            if (std::isfinite(step.gpu_kernel_ms))
                markdown << step.gpu_kernel_ms;
            else
                markdown << "n/a";
            markdown << " | ";
            if (step.error_available)
                markdown << step.error.mixed_error;
            else
                markdown << "n/a";
            markdown << " | " << (step.pass ? "PASS" : "PENDING") << " |\n";
        }
    }
}
