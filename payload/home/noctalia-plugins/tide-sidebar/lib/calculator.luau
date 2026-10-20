-- Pure Lua/Luau arithmetic. Never executes input as code.
-- evaluate(expression, ans?) -> number | nil, {code, message, position?} | nil
-- Percent is always postfix division by 100: 200 + 10% == 200.1.
-- Powers associate right; exponentiation binds tighter than a leading sign.
-- Error positions are one-based byte offsets in the original input.
local Calculator = {}

Calculator.MAX_EXPRESSION_LENGTH = 1024
Calculator.MAX_TOKENS = 512
Calculator.MAX_NESTING = 64

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function failure(code, message, position)
    return { code = code, message = message, position = position }
end

local function fail(code, message, position)
    error(failure(code, message, position), 0)
end

local function checked(value, position)
    if value ~= value then
        fail("domain_error", "此运算没有实数结果", position)
    end
    if not finite(value) then
        fail("non_finite_result", "结果超出可计算范围", position)
    end
    return value
end

local function digit(byte)
    return byte ~= nil and byte >= 48 and byte <= 57
end

local function letter(byte)
    return byte ~= nil and ((byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122) or byte == 95)
end

local function tokenize(expression)
    local tokens = {}
    local length = #expression
    local cursor = 1
    local function add(kind, value, position)
        if #tokens >= Calculator.MAX_TOKENS then
            fail("expression_too_complex", "表达式包含太多内容", position)
        end
        tokens[#tokens + 1] = { kind = kind, value = value, position = position }
    end
    while cursor <= length do
        local byte = string.byte(expression, cursor)
        local char = string.sub(expression, cursor, cursor)
        local pair = string.sub(expression, cursor, cursor + 1)
        if byte == 32 or (byte >= 9 and byte <= 13) then
            cursor = cursor + 1
        elseif digit(byte) or char == "." then
            local start = cursor
            local digits = 0
            while digit(string.byte(expression, cursor)) do
                cursor = cursor + 1
                digits = digits + 1
            end
            if string.sub(expression, cursor, cursor) == "." then
                cursor = cursor + 1
                while digit(string.byte(expression, cursor)) do
                    cursor = cursor + 1
                    digits = digits + 1
                end
            end
            if digits == 0 then
                fail("invalid_number", "小数点前后至少需要一个数字", start)
            end
            local exponent = string.sub(expression, cursor, cursor)
            if exponent == "e" or exponent == "E" then
                cursor = cursor + 1
                local sign = string.sub(expression, cursor, cursor)
                if sign == "+" or sign == "-" then
                    cursor = cursor + 1
                end
                local exponentStart = cursor
                while digit(string.byte(expression, cursor)) do
                    cursor = cursor + 1
                end
                if cursor == exponentStart then
                    fail("invalid_number", "科学记数法的指数不完整；常数 e 前请使用乘号", start)
                end
            end
            local value = tonumber(string.sub(expression, start, cursor - 1))
            if not finite(value) then
                fail("invalid_number", "数字无效或超出可计算范围", start)
            end
            -- Lua may otherwise use wrapping integer arithmetic; Luau uses doubles.
            add("number", value + 0.0, start)
        elseif letter(byte) then
            local start = cursor
            repeat
                cursor = cursor + 1
                byte = string.byte(expression, cursor)
            until not (letter(byte) or digit(byte))
            add("name", string.lower(string.sub(expression, start, cursor - 1)), start)
        elseif pair == "π" then
            add("name", "pi", cursor)
            cursor = cursor + #pair
        elseif pair == "×" or pair == "÷" then
            add(pair == "×" and "*" or "/", nil, cursor)
            cursor = cursor + #pair
        elseif string.sub(expression, cursor, cursor + 2) == "−" then
            add("-", nil, cursor)
            cursor = cursor + 3
        elseif char == "+" or char == "-" or char == "*" or char == "/"
            or char == "^" or char == "%" or char == "(" or char == ")" then
            add(char, nil, cursor)
            cursor = cursor + 1
        else
            fail("invalid_character", "包含不支持的字符", cursor)
        end
    end
    tokens[#tokens + 1] = { kind = "end", position = length + 1 }
    return tokens
end

local function parse(expression, answer)
    local tokens = tokenize(expression)
    local cursor = 1
    local depth = 0
    local parseSum
    local parseUnary

    local function current()
        return tokens[cursor]
    end

    local function consume()
        local token = current()
        cursor = cursor + 1
        return token
    end

    local function parenthesized()
        local opening = current()
        if opening.kind ~= "(" then
            fail("expected_parenthesis", "函数参数需要放在括号内", opening.position)
        end
        consume()
        local result = parseSum()
        if current().kind ~= ")" then
            fail("unmatched_parenthesis", "缺少右括号", current().position)
        end
        consume()
        return result
    end

    local function primary()
        local token = current()
        if token.kind == "number" then
            consume()
            return token.value
        elseif token.kind == "(" then
            return parenthesized()
        elseif token.kind == "name" then
            consume()
            if token.value == "pi" then
                return math.pi
            elseif token.value == "e" then
                return math.exp(1)
            elseif token.value == "ans" then
                return answer
            elseif token.value == "sqrt" or token.value == "abs" then
                local argument = parenthesized()
                if token.value == "abs" then
                    return math.abs(argument)
                end
                if argument < 0 then
                    fail("domain_error", "负数不能开实数平方根", token.position)
                end
                return math.sqrt(argument)
            end
            fail("unknown_identifier", "只支持 pi、π、e、ans、sqrt 和 abs", token.position)
        end
        fail("unexpected_token", "此处需要数字、常数或左括号", token.position)
    end

    local function postfix()
        local result = primary()
        while current().kind == "%" do
            consume()
            result = result / 100
        end
        return result
    end

    local function power()
        local result = postfix()
        if current().kind == "^" then
            local operator = consume()
            local exponent = parseUnary()
            if result == 0 and exponent < 0 then
                fail("division_by_zero", "零不能取负指数（相当于除以零）", operator.position)
            end
            result = checked(result ^ exponent, operator.position)
        end
        return result
    end

    parseUnary = function()
        depth = depth + 1
        if depth > Calculator.MAX_NESTING then
            fail("expression_too_complex", "表达式嵌套过深", current().position)
        end
        local token = current()
        local result
        if token.kind == "+" or token.kind == "-" then
            consume()
            result = parseUnary()
            if token.kind == "-" then
                result = -result
            end
        else
            result = power()
        end
        depth = depth - 1
        return result
    end

    local function product()
        local result = parseUnary()
        while current().kind == "*" or current().kind == "/" do
            local operator = consume()
            local right = parseUnary()
            if operator.kind == "*" then
                result = checked(result * right, operator.position)
            else
                if right == 0 then
                    fail("division_by_zero", "不能除以零", operator.position)
                end
                result = checked(result / right, operator.position)
            end
        end
        return result
    end

    parseSum = function()
        local result = product()
        while current().kind == "+" or current().kind == "-" do
            local operator = consume()
            local right = product()
            if operator.kind == "+" then
                result = checked(result + right, operator.position)
            else
                result = checked(result - right, operator.position)
            end
        end
        return result
    end

    if current().kind == "end" then
        fail("empty_expression", "请输入算式", current().position)
    end
    local result = parseSum()
    if current().kind ~= "end" then
        fail("unexpected_token", "此处需要运算符；相邻数值请使用乘号", current().position)
    end
    return result
end

function Calculator.evaluate(expression, ans)
    if type(expression) ~= "string" then
        return nil, failure("invalid_expression", "算式必须是文本")
    end
    if #expression > Calculator.MAX_EXPRESSION_LENGTH then
        return nil, failure("expression_too_long", "算式过长，请缩短后再试", Calculator.MAX_EXPRESSION_LENGTH + 1)
    end
    if ans == nil then
        ans = 0
    end
    if not finite(ans) then
        return nil, failure("invalid_answer", "上次答案必须是有限数字")
    end
    local ok, result = pcall(parse, expression, ans + 0.0)
    if not ok then
        if type(result) == "table" and type(result.code) == "string" then
            return nil, result
        end
        return nil, failure("invalid_expression", "无法计算该表达式")
    end
    if result == 0 then
        result = 0 -- Normalize negative zero for both the result and display.
    end
    return result, nil
end

function Calculator.format(value)
    if not finite(value) then
        return "—"
    end
    if value == 0 then
        return "0"
    end
    return string.format("%.15g", value)
end

return Calculator
