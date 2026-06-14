#pragma once

#include <cctype>
#include <cstddef>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <variant>
#include <vector>

namespace cusignal_test
{
    namespace json
    {
        class Value;

        using Array = std::vector<Value>;
        using Object = std::map<std::string, Value>;

        class Value
        {
        public:
            using Storage = std::variant<std::nullptr_t, bool, float, std::string, Array, Object>;

            Value() : storage_(nullptr) {}
            Value(std::nullptr_t) : storage_(nullptr) {}
            Value(bool value) : storage_(value) {}
            Value(float value) : storage_(value) {}
            Value(std::string value) : storage_(std::move(value)) {}
            Value(const char *value) : storage_(std::string(value)) {}
            Value(Array value) : storage_(std::move(value)) {}
            Value(Object value) : storage_(std::move(value)) {}

            bool is_null() const { return std::holds_alternative<std::nullptr_t>(storage_); }
            bool is_bool() const { return std::holds_alternative<bool>(storage_); }
            bool is_number() const { return std::holds_alternative<float>(storage_); }
            bool is_string() const { return std::holds_alternative<std::string>(storage_); }
            bool is_array() const { return std::holds_alternative<Array>(storage_); }
            bool is_object() const { return std::holds_alternative<Object>(storage_); }

            bool as_bool() const
            {
                return std::get<bool>(storage_);
            }

            float as_number() const
            {
                return std::get<float>(storage_);
            }

            const std::string &as_string() const
            {
                return std::get<std::string>(storage_);
            }

            const Array &as_array() const
            {
                return std::get<Array>(storage_);
            }

            const Object &as_object() const
            {
                return std::get<Object>(storage_);
            }

            const Value &at(const std::string &key) const
            {
                return as_object().at(key);
            }

            bool contains(const std::string &key) const
            {
                if (!is_object())
                {
                    return false;
                }
                return as_object().find(key) != as_object().end();
            }

        private:
            Storage storage_;
        };

        class Parser
        {
        public:
            explicit Parser(std::string text) : text_(std::move(text)) {}

            Value parse()
            {
                skip_whitespace();
                Value value = parse_value();
                skip_whitespace();
                if (position_ != text_.size())
                {
                    throw std::runtime_error("unexpected trailing JSON content");
                }
                return value;
            }

        private:
            void skip_whitespace()
            {
                while (position_ < text_.size() &&
                       std::isspace(static_cast<unsigned char>(text_[position_])))
                {
                    ++position_;
                }
            }

            char peek() const
            {
                if (position_ >= text_.size())
                {
                    throw std::runtime_error("unexpected end of JSON");
                }
                return text_[position_];
            }

            char consume()
            {
                const char value = peek();
                ++position_;
                return value;
            }

            void expect(char value)
            {
                if (consume() != value)
                {
                    std::ostringstream stream;
                    stream << "expected '" << value << "'";
                    throw std::runtime_error(stream.str());
                }
            }

            Value parse_value()
            {
                skip_whitespace();
                const char token = peek();
                if (token == 'n')
                {
                    parse_literal("null");
                    return Value(nullptr);
                }
                if (token == 't')
                {
                    parse_literal("true");
                    return Value(true);
                }
                if (token == 'f')
                {
                    parse_literal("false");
                    return Value(false);
                }
                if (token == '"')
                {
                    return Value(parse_string());
                }
                if (token == '[')
                {
                    return Value(parse_array());
                }
                if (token == '{')
                {
                    return Value(parse_object());
                }
                if (token == '-' || std::isdigit(static_cast<unsigned char>(token)))
                {
                    return Value(parse_number());
                }

                throw std::runtime_error("unexpected JSON token");
            }

            void parse_literal(const std::string &literal)
            {
                for (char expected : literal)
                {
                    if (consume() != expected)
                    {
                        throw std::runtime_error("invalid JSON literal");
                    }
                }
            }

            std::string parse_string()
            {
                expect('"');
                std::string result;
                while (true)
                {
                    const char value = consume();
                    if (value == '"')
                    {
                        break;
                    }
                    if (value == '\\')
                    {
                        const char escaped = consume();
                        switch (escaped)
                        {
                        case '"':
                        case '\\':
                        case '/':
                            result.push_back(escaped);
                            break;
                        case 'b':
                            result.push_back('\b');
                            break;
                        case 'f':
                            result.push_back('\f');
                            break;
                        case 'n':
                            result.push_back('\n');
                            break;
                        case 'r':
                            result.push_back('\r');
                            break;
                        case 't':
                            result.push_back('\t');
                            break;
                        default:
                            throw std::runtime_error("unsupported JSON escape sequence");
                        }
                        continue;
                    }
                    result.push_back(value);
                }
                return result;
            }

            float parse_number()
            {
                const std::size_t start = position_;
                if (peek() == '-')
                {
                    ++position_;
                }
                consume_digits();
                if (position_ < text_.size() && text_[position_] == '.')
                {
                    ++position_;
                    consume_digits();
                }
                if (position_ < text_.size() &&
                    (text_[position_] == 'e' || text_[position_] == 'E'))
                {
                    ++position_;
                    if (text_[position_] == '+' || text_[position_] == '-')
                    {
                        ++position_;
                    }
                    consume_digits();
                }
                return std::stod(text_.substr(start, position_ - start));
            }

            void consume_digits()
            {
                if (position_ >= text_.size() ||
                    !std::isdigit(static_cast<unsigned char>(text_[position_])))
                {
                    throw std::runtime_error("expected JSON digits");
                }

                while (position_ < text_.size() &&
                       std::isdigit(static_cast<unsigned char>(text_[position_])))
                {
                    ++position_;
                }
            }

            Array parse_array()
            {
                expect('[');
                skip_whitespace();
                Array array;
                if (peek() == ']')
                {
                    consume();
                    return array;
                }

                while (true)
                {
                    array.push_back(parse_value());
                    skip_whitespace();
                    const char token = consume();
                    if (token == ']')
                    {
                        break;
                    }
                    if (token != ',')
                    {
                        throw std::runtime_error("expected ',' or ']'");
                    }
                    skip_whitespace();
                }

                return array;
            }

            Object parse_object()
            {
                expect('{');
                skip_whitespace();
                Object object;
                if (peek() == '}')
                {
                    consume();
                    return object;
                }

                while (true)
                {
                    const std::string key = parse_string();
                    skip_whitespace();
                    expect(':');
                    skip_whitespace();
                    object.emplace(key, parse_value());
                    skip_whitespace();
                    const char token = consume();
                    if (token == '}')
                    {
                        break;
                    }
                    if (token != ',')
                    {
                        throw std::runtime_error("expected ',' or '}'");
                    }
                    skip_whitespace();
                }

                return object;
            }

            std::string text_;
            std::size_t position_ = 0;
        };

        inline Value parse(const std::string &text)
        {
            return Parser(text).parse();
        }

    } // namespace json
} // namespace cusignal_test
