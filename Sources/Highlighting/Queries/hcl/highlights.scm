; The HCL grammar ships no queries; this covers Terraform and Nomad files.
(comment) @comment

(string_lit) @string
(quoted_template_start) @string
(quoted_template_end) @string
(template_literal) @string
(heredoc_identifier) @string
(heredoc_start) @string

(numeric_lit) @number
(bool_lit) @boolean
(null_lit) @constant.builtin

(block (identifier) @keyword)
(block (string_lit) @string.special)
(attribute (identifier) @property)
(get_attr (identifier) @property)
(function_call (identifier) @function.call)
(variable_expr (identifier) @variable)

["for" "in" "if" "else" "endif" "endfor"] @keyword

["!" "!=" "%" "&&" "*" "+" "-" "/" ":" "<" "<=" "=" "==" "=>" ">" ">=" "?" "||" ".*" "[*]"] @operator
["<<" "<<-"] @punctuation.special
["{" "}" "[" "]" "(" ")"] @punctuation.bracket
["." ","] @punctuation.delimiter
(template_interpolation_start) @punctuation.special
(template_interpolation_end) @punctuation.special
(ellipsis) @punctuation.special
