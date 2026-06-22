use super::operators::all_operators;
use super::types::{Location, MutationKind, MutationSite, Span};

/// Scan R source text and return all sites where mutations can be applied.
pub fn scan_source(source: &str, file_name: &str) -> Vec<MutationSite> {
    let ops = all_operators();
    let bytes = source.as_bytes();
    let len = bytes.len();
    let mut sites: Vec<MutationSite> = Vec::new();
    let mut pos: usize = 0;
    let mut line: usize = 1;
    let mut col: usize = 1;
    let mut in_string: Option<u8> = None;

    while pos < len {
        let b = bytes[pos];

        // Track string state
        if let Some(delim) = in_string {
            if b == b'\\' {
                // Skip escaped character
                pos += 2;
                col += 2;
                continue;
            }
            if b == delim {
                in_string = None;
            }
            if b == b'\n' {
                line += 1;
                col = 1;
            } else {
                col += 1;
            }
            pos += 1;
            continue;
        }

        // Enter string
        if b == b'"' || b == b'\'' {
            in_string = Some(b);
            pos += 1;
            col += 1;
            continue;
        }

        // Comment: skip to end of line
        if b == b'#' {
            while pos < len && bytes[pos] != b'\n' {
                pos += 1;
            }
            continue;
        }

        // Newline
        if b == b'\n' {
            line += 1;
            col = 1;
            pos += 1;
            continue;
        }

        // Check for R assignment operators: <- and <<-
        if b == b'<' {
            if pos + 1 < len && bytes[pos + 1] == b'-' {
                // Try function-body detection: name <- function(...) { ... }
                let assign_pos = pos;
                let after_arrow = pos + 2;

                // Scan backward from '<' (skip whitespace) for function name
                let mut name_end = assign_pos;
                while name_end > 0 && (bytes[name_end - 1] == b' ' || bytes[name_end - 1] == b'\t')
                {
                    name_end -= 1;
                }
                let mut name_start = name_end;
                while name_start > 0 && is_r_ident_char(bytes[name_start - 1]) {
                    name_start -= 1;
                }
                let fname = if name_start < name_end {
                    Some(std::str::from_utf8(&bytes[name_start..name_end]).unwrap_or(""))
                } else {
                    None
                };

                // Check: name must exist and not be "new"
                let should_scan_body = match fname {
                    Some(n) => !n.is_empty() && n != "new",
                    None => false,
                };

                if should_scan_body {
                    // Scan forward: skip whitespace after '<-'
                    let mut scan = after_arrow;
                    while scan < len && (bytes[scan] == b' ' || bytes[scan] == b'\t') {
                        scan += 1;
                    }

                    // Check for 'function' keyword (8 bytes) with word boundary
                    if scan + 8 <= len && &bytes[scan..scan + 8] == b"function" {
                        let after_func = scan + 8;
                        let word_boundary =
                            after_func >= len || !is_r_ident_char(bytes[after_func]);
                        if word_boundary {
                            scan = after_func;

                            // Skip whitespace, expect '('
                            while scan < len
                                && (bytes[scan] == b' '
                                    || bytes[scan] == b'\t'
                                    || bytes[scan] == b'\n')
                            {
                                scan += 1;
                            }

                            if scan < len && bytes[scan] == b'(' {
                                // Track paren depth to find matching ')'
                                let mut paren_depth: usize = 1;
                                let mut paren_in_str: Option<u8> = None;
                                scan += 1; // skip '('
                                while scan < len && paren_depth > 0 {
                                    let pc = bytes[scan];
                                    if let Some(d) = paren_in_str {
                                        if pc == b'\\' {
                                            scan += 1;
                                        } else if pc == d {
                                            paren_in_str = None;
                                        }
                                    } else if pc == b'"' || pc == b'\'' {
                                        paren_in_str = Some(pc);
                                    } else if pc == b'#' {
                                        while scan < len && bytes[scan] != b'\n' {
                                            scan += 1;
                                        }
                                        continue;
                                    } else if pc == b'(' {
                                        paren_depth += 1;
                                    } else if pc == b')' {
                                        paren_depth -= 1;
                                    }
                                    scan += 1;
                                }

                                // After ')', skip whitespace/newlines, expect '{'
                                while scan < len
                                    && (bytes[scan] == b' '
                                        || bytes[scan] == b'\t'
                                        || bytes[scan] == b'\n')
                                {
                                    scan += 1;
                                }

                                if scan < len && bytes[scan] == b'{' {
                                    let open_brace = scan;
                                    if let Some(close_brace) =
                                        find_matching_brace(bytes, open_brace)
                                    {
                                        // Check if body is noop (equivalent to return(NULL))
                                        let body_text = std::str::from_utf8(
                                            &bytes[open_brace + 1..close_brace],
                                        )
                                        .unwrap_or("");
                                        let trimmed = body_text.trim();
                                        let is_noop = trimmed.is_empty()
                                            || trimmed == "NULL"
                                            || trimmed == "return(NULL)"
                                            || trimmed == "return (NULL)";
                                        if !is_noop {
                                            // Compute line/col for open_brace position
                                            let body_line =
                                                source[..open_brace].matches('\n').count() + 1;
                                            let body_col = match source[..open_brace].rfind('\n') {
                                                Some(p) => open_brace - p,
                                                None => open_brace + 1,
                                            };

                                            let body_span = Span {
                                                start: open_brace,
                                                end: close_brace + 1,
                                            };
                                            let original = std::str::from_utf8(
                                                &bytes[open_brace..close_brace + 1],
                                            )
                                            .unwrap_or("")
                                            .to_string();

                                            sites.push(MutationSite {
                                                location: Location {
                                                    file: file_name.to_string(),
                                                    line: body_line,
                                                    col: body_col,
                                                    span: body_span.clone(),
                                                },
                                                original,
                                                kind: MutationKind::FunctionBody {
                                                    name: fname.unwrap().to_string(),
                                                    body_span: body_span.clone(),
                                                },
                                                replacements: vec!["{ return(NULL) }".to_string()],
                                            });
                                        }

                                        // Advance position to inside body (after opening brace)
                                        // so internal operators/numerics are still detected.
                                        let new_pos = open_brace + 1;
                                        let old_pos = assign_pos;
                                        for &cb in &bytes[old_pos..new_pos] {
                                            if cb == b'\n' {
                                                line += 1;
                                                col = 1;
                                            } else {
                                                col += 1;
                                            }
                                        }
                                        pos = new_pos;
                                        continue;
                                    }
                                }
                            }
                        }
                    }
                }

                // Fall through: normal <- skip (no function body detected)
                pos += 2;
                col += 2;
                continue;
            }
            if pos + 2 < len && bytes[pos + 1] == b'<' && bytes[pos + 2] == b'-' {
                // <<-  skip all three chars
                pos += 3;
                col += 3;
                continue;
            }
        }

        // Try numeric literal detection (before operator registry)
        if let Some((end, original)) = try_scan_numeric_literal(bytes, pos) {
            let replacements = numeric_replacements(&original);
            sites.push(MutationSite {
                location: Location {
                    file: file_name.to_string(),
                    line,
                    col,
                    span: Span { start: pos, end },
                },
                original,
                kind: MutationKind::Numeric,
                replacements,
            });
            let advanced = end - pos;
            pos = end;
            col += advanced;
            continue;
        }

        // Try to match operators (longest first due to sort order)
        let remaining = &source[pos..];
        let mut matched = false;

        // Group operators by `from` to collect all replacements for a single site
        let mut i = 0;
        while i < ops.len() {
            let op = &ops[i];
            if !remaining.starts_with(op.from) {
                i += 1;
                continue;
            }

            // Word boundary check for boolean literals (TRUE, FALSE)
            if op.kind == MutationKind::Boolean {
                let before_ok = if pos == 0 {
                    true
                } else {
                    !is_r_ident_char(bytes[pos - 1])
                };
                let after_pos = pos + op.from.len();
                let after_ok = if after_pos >= len {
                    true
                } else {
                    !is_r_ident_char(bytes[after_pos])
                };
                if !before_ok || !after_ok {
                    i += 1;
                    continue;
                }
            }

            // Collect all replacements for this `from` token
            let from = op.from;
            let kind = op.kind.clone();
            let mut replacements: Vec<String> = Vec::new();
            let mut j = i;
            while j < ops.len() {
                if ops[j].from == from {
                    replacements.push(ops[j].to.to_string());
                    j += 1;
                } else {
                    break;
                }
            }

            sites.push(MutationSite {
                location: Location {
                    file: file_name.to_string(),
                    line,
                    col,
                    span: Span {
                        start: pos,
                        end: pos + from.len(),
                    },
                },
                original: from.to_string(),
                kind,
                replacements,
            });

            pos += from.len();
            col += from.len();
            matched = true;
            break;
        }

        if !matched {
            pos += 1;
            col += 1;
        }
    }

    sites
}

/// Returns true if the byte is a valid R identifier character: [a-zA-Z0-9_.]
fn is_r_ident_char(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_' || b == b'.'
}

/// Try to scan a numeric literal starting at `pos`.
///
/// Returns `Some((end_pos, literal_str))` if a valid numeric literal is found,
/// or `None` if the position does not start a numeric literal.
///
/// Detection rules:
/// - Starts with a digit or `.` followed by a digit
/// - Followed by optional digits, optional `.` + digits, optional `e`/`E` + optional `+`/`-` + digits
/// - Before-boundary: char before must NOT be `is_r_ident_char`
/// - After-boundary: char after must NOT be `is_r_ident_char` (rejects `1L`, `1i`, `0x1F`, etc.)
fn try_scan_numeric_literal(bytes: &[u8], pos: usize) -> Option<(usize, String)> {
    let len = bytes.len();
    if pos >= len {
        return None;
    }

    let start_pos = pos;

    // Must start with a digit or '.' followed by a digit
    let b = bytes[pos];
    match b {
        _ if b.is_ascii_digit() => {}
        b'.' => {
            if pos + 1 >= len || !bytes[pos + 1].is_ascii_digit() {
                return None;
            }
        }
        _ => return None,
    }

    // Before-boundary check
    if start_pos > 0 {
        let before = bytes[start_pos - 1];
        if is_r_ident_char(before) {
            return None;
        }
    }

    // Scan the literal body
    let mut end = pos;

    // Integer part
    if bytes[end].is_ascii_digit() {
        end += 1;
        while end < len && bytes[end].is_ascii_digit() {
            end += 1;
        }
    }

    // Optional fractional part
    if end < len && bytes[end] == b'.' {
        let dot_pos = end;
        end += 1;
        if end < len && bytes[end].is_ascii_digit() {
            while end < len && bytes[end].is_ascii_digit() {
                end += 1;
            }
        } else {
            // Dot not followed by digit — backtrack (not a fractional part)
            end = dot_pos;
        }
    }

    // Optional exponent part
    if end < len && (bytes[end] == b'e' || bytes[end] == b'E') {
        let exp_start = end;
        end += 1;
        if end < len && (bytes[end] == b'+' || bytes[end] == b'-') {
            end += 1;
        }
        if end < len && bytes[end].is_ascii_digit() {
            while end < len && bytes[end].is_ascii_digit() {
                end += 1;
            }
        } else {
            // Not a valid exponent — backtrack
            end = exp_start;
        }
    }

    // Must have consumed at least one character
    if end == start_pos {
        return None;
    }

    // After-boundary check: next char must NOT be an R ident char
    // This rejects R suffixes like L, i, and hex prefix 0x
    if end < len && is_r_ident_char(bytes[end]) {
        return None;
    }

    let literal = std::str::from_utf8(&bytes[start_pos..end])
        .ok()?
        .to_string();
    Some((end, literal))
}

/// Compute replacement values for a numeric literal.
///
/// - Integer 0 → ["1"]
/// - Integer 1 → ["0"]
/// - Integer n > 1 → ["0", "1", "-1"]
/// - Float 0.0 → ["1.0"]
/// - Float 1.0 → ["0.0"]
/// - Float n.f → ["0.0", "1.0", "-1.0"]
fn numeric_replacements(original: &str) -> Vec<String> {
    let is_float = original.contains('.') || original.contains('e') || original.contains('E');

    // Parse the numeric value to determine if it's 0 or 1
    if let Ok(val) = original.parse::<f64>() {
        if val == 0.0 {
            return if is_float {
                vec!["1.0".to_string()]
            } else {
                vec!["1".to_string()]
            };
        }
        if val == 1.0 {
            return if is_float {
                vec!["0.0".to_string()]
            } else {
                vec!["0".to_string()]
            };
        }
    }

    // Default: value is not 0 or 1 (or parsing failed)
    if is_float {
        vec!["0.0".to_string(), "1.0".to_string(), "-1.0".to_string()]
    } else {
        vec!["0".to_string(), "1".to_string(), "-1".to_string()]
    }
}

/// Find the matching closing brace `}` for the `{` at `open_pos`.
///
/// Tracks brace depth, string literals, escape sequences in strings,
/// and comments to correctly handle braces in those contexts.
/// Returns `None` if the brace is unclosed (no panic).
pub fn find_matching_brace(bytes: &[u8], open_pos: usize) -> Option<usize> {
    if open_pos >= bytes.len() || bytes[open_pos] != b'{' {
        return None;
    }

    let mut depth: usize = 1;
    let mut pos = open_pos + 1;
    let mut in_string: Option<u8> = None;

    while pos < bytes.len() {
        let b = bytes[pos];

        if let Some(delim) = in_string {
            if b == b'\\' {
                pos += 2;
                continue;
            }
            if b == delim {
                in_string = None;
            }
            pos += 1;
            continue;
        }

        if b == b'"' || b == b'\'' {
            in_string = Some(b);
            pos += 1;
            continue;
        }

        if b == b'#' {
            // Skip to end of line
            while pos < bytes.len() && bytes[pos] != b'\n' {
                pos += 1;
            }
            continue;
        }

        if b == b'{' {
            depth += 1;
        } else if b == b'}' {
            depth -= 1;
            if depth == 0 {
                return Some(pos);
            }
        }

        pos += 1;
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_source_returns_no_sites() {
        let sites = scan_source("", "test.R");
        assert!(sites.is_empty());
    }

    #[test]
    fn finds_equality_operator() {
        let sites = scan_source("x == y", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "==");
        assert_eq!(sites[0].replacements, vec!["!="]);
        assert_eq!(sites[0].location.line, 1);
        assert_eq!(sites[0].location.col, 3);
    }

    #[test]
    fn finds_true_literal() {
        let sites = scan_source("TRUE", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "TRUE");
        assert_eq!(sites[0].replacements, vec!["FALSE"]);
    }

    #[test]
    fn skips_comment() {
        let sites = scan_source("# x == y", "test.R");
        assert!(sites.is_empty());
    }

    #[test]
    fn finds_multiple_operators() {
        let sites = scan_source("x + y - z", "test.R");
        assert_eq!(sites.len(), 2);
        assert_eq!(sites[0].original, "+");
        assert_eq!(sites[1].original, "-");
    }

    #[test]
    fn tracks_line_and_col_across_newlines() {
        let sites = scan_source("x\ny == z", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].location.line, 2);
        assert_eq!(sites[0].location.col, 3);
        assert_eq!(sites[0].location.span.start, 4);
        assert_eq!(sites[0].location.span.end, 6);
    }

    #[test]
    fn span_is_correct_for_multi_char_operator() {
        let sites = scan_source("x == y", "test.R");
        assert_eq!(sites[0].location.span.start, 2);
        assert_eq!(sites[0].location.span.end, 4);
    }

    #[test]
    fn skips_double_quoted_string() {
        let sites = scan_source("\"x == y\"", "test.R");
        assert!(sites.is_empty());
    }

    #[test]
    fn skips_single_quoted_string() {
        let sites = scan_source("'x == y'", "test.R");
        assert!(sites.is_empty());
    }

    #[test]
    fn handles_escaped_quote_in_string() {
        // The \" inside the string should not end it
        let sites = scan_source(r#""x \" == y""#, "test.R");
        assert!(sites.is_empty());
    }

    #[test]
    fn finds_operator_after_string() {
        let sites = scan_source("\"hello\" == \"world\"", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "==");
    }

    #[test]
    fn skips_assignment_operator() {
        // <- is skipped; 5 after it is a numeric literal
        let sites = scan_source("x <- 5", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "5");
        assert_eq!(sites[0].kind, MutationKind::Numeric);
    }

    #[test]
    fn skips_super_assignment_operator() {
        // <<- is skipped; 5 after it is a numeric literal
        let sites = scan_source("x <<- 5", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "5");
        assert_eq!(sites[0].kind, MutationKind::Numeric);
    }

    #[test]
    fn finds_less_than_when_not_assignment() {
        let sites = scan_source("x < y", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "<");
        assert_eq!(sites[0].replacements, vec![">="]);
    }

    #[test]
    fn assignment_then_comparison_on_next_line() {
        // 5 is a numeric literal on line 1, < is an operator on line 2
        let sites = scan_source("x <- 5\ny < z", "test.R");
        assert_eq!(sites.len(), 2);
        assert_eq!(sites[0].original, "5");
        assert_eq!(sites[0].kind, MutationKind::Numeric);
        assert_eq!(sites[0].location.line, 1);
        assert_eq!(sites[1].original, "<");
        assert_eq!(sites[1].location.line, 2);
    }

    #[test]
    fn true_with_word_boundary_before() {
        // dot is an R identifier char, so .TRUE should not match
        let sites = scan_source(".TRUE", "test.R");
        assert!(sites.is_empty());
    }

    #[test]
    fn true_with_underscore_boundary() {
        let sites = scan_source("_TRUE", "test.R");
        assert!(sites.is_empty());
    }

    #[test]
    fn true_after_open_paren() {
        let sites = scan_source("(TRUE)", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "TRUE");
    }

    #[test]
    fn false_at_end_of_source() {
        let sites = scan_source("FALSE", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "FALSE");
        assert_eq!(sites[0].replacements, vec!["TRUE"]);
    }

    #[test]
    fn is_r_ident_char_letters() {
        assert!(is_r_ident_char(b'a'));
        assert!(is_r_ident_char(b'Z'));
        assert!(is_r_ident_char(b'0'));
        assert!(is_r_ident_char(b'_'));
        assert!(is_r_ident_char(b'.'));
    }

    #[test]
    fn is_r_ident_char_non_ident() {
        assert!(!is_r_ident_char(b' '));
        assert!(!is_r_ident_char(b'('));
        assert!(!is_r_ident_char(b')'));
        assert!(!is_r_ident_char(b'+'));
        assert!(!is_r_ident_char(b'\n'));
    }

    #[test]
    fn finds_logical_and_operator() {
        let sites = scan_source("a && b", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "&&");
        assert_eq!(sites[0].replacements, vec!["||"]);
    }

    #[test]
    fn finds_logical_or_operator() {
        let sites = scan_source("a || b", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "||");
        assert_eq!(sites[0].replacements, vec!["&&"]);
    }

    #[test]
    fn finds_single_and_operator() {
        let sites = scan_source("a & b", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "&");
        assert_eq!(sites[0].replacements, vec!["|"]);
    }

    #[test]
    fn finds_single_or_operator() {
        let sites = scan_source("a | b", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "|");
        assert_eq!(sites[0].replacements, vec!["&"]);
    }

    #[test]
    fn comment_after_code_skips_rest_of_line() {
        let sites = scan_source("x == y # z != w", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "==");
    }

    #[test]
    fn col_advances_correctly_after_operator() {
        // "a + b - c" — + at col 3, - at col 7
        let sites = scan_source("a + b - c", "test.R");
        assert_eq!(sites[0].location.col, 3);
        assert_eq!(sites[1].location.col, 7);
    }

    #[test]
    fn multiline_string_does_not_leak() {
        let sites = scan_source("\"line1\nline2\" == x", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "==");
    }

    #[test]
    fn less_than_equal_not_split() {
        let sites = scan_source("x <= y", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "<=");
        assert_eq!(sites[0].replacements, vec![">"]);
    }

    #[test]
    fn finds_not_equal() {
        let sites = scan_source("x != y", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "!=");
        assert_eq!(sites[0].replacements, vec!["=="]);
    }

    #[test]
    fn finds_multiply_and_divide() {
        let sites = scan_source("x * y / z", "test.R");
        assert_eq!(sites.len(), 2);
        assert_eq!(sites[0].original, "*");
        assert_eq!(sites[0].replacements, vec!["/"]);
        assert_eq!(sites[1].original, "/");
        assert_eq!(sites[1].replacements, vec!["*"]);
    }

    #[test]
    fn file_name_is_preserved() {
        let sites = scan_source("TRUE", "my_file.R");
        assert_eq!(sites[0].location.file, "my_file.R");
    }

    #[test]
    fn greater_than_equal() {
        let sites = scan_source("x >= y", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, ">=");
        assert_eq!(sites[0].replacements, vec!["<"]);
    }

    #[test]
    fn greater_than() {
        let sites = scan_source("x > y", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, ">");
        assert_eq!(sites[0].replacements, vec!["<="]);
    }

    #[test]
    fn escaped_quote_position_tracking() {
        // After "ab\"cd", the == should be found at the correct position
        let sites = scan_source(r#""ab\"cd" == x"#, "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "==");
        assert_eq!(sites[0].location.col, 10);
    }

    #[test]
    fn newline_in_string_tracks_line_correctly() {
        // A newline inside a string should advance line counter
        let sites = scan_source("\"line1\nline2\"\nTRUE", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "TRUE");
        assert_eq!(sites[0].location.line, 3);
    }

    #[test]
    fn col_resets_after_string_newline() {
        let sites = scan_source("\"a\nb\" == x", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].location.line, 2);
        // After "b" (col 2) then closing " (col 3) then space (col 4) then ==
        assert_eq!(sites[0].location.col, 4);
    }

    #[test]
    fn assignment_skips_exactly_two_chars() {
        // "x <- == y" — <- takes 2 chars, then space, then == should be found
        let sites = scan_source("x<-== y", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "==");
        assert_eq!(sites[0].location.col, 4);
    }

    #[test]
    fn super_assignment_skips_exactly_three_chars() {
        // "x<<-== y" — <<- takes 3 chars, then == should be found
        let sites = scan_source("x<<-== y", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "==");
        assert_eq!(sites[0].location.col, 5);
    }

    #[test]
    fn string_col_advances_for_normal_chars() {
        // "ab" then == — col should be 5 (1 for opening ", 2 for a, 3 for b, 4 for closing ", 5 for space... wait)
        // "ab" == x  → " at col 1, a at col 2, b at col 3, " at col 4, space at col 5, == at col 6
        let sites = scan_source("\"ab\" == x", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].location.col, 6);
    }

    #[test]
    fn enter_string_advances_col() {
        // Make sure entering a string with ' also works
        let sites = scan_source("'ab' == x", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].location.col, 6);
    }

    #[test]
    fn super_assignment_requires_all_three_chars() {
        // "x<<y" should find << as two < operators? No — << is not a valid R operator.
        // Actually < < would be two less-thans. Let's test that <<- is only skipped when
        // all three chars match: < then < then -
        let sites = scan_source("x << y", "test.R");
        // This should find two < operators (since << is not an operator, and <<- pattern requires -)
        assert_eq!(sites.len(), 2);
        assert_eq!(sites[0].original, "<");
        assert_eq!(sites[1].original, "<");
    }

    // ── Numeric literal detection tests ──

    #[test]
    fn detects_integer_zero() {
        let sites = scan_source("0", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "0");
        assert_eq!(sites[0].kind, MutationKind::Numeric);
        assert_eq!(sites[0].replacements, vec!["1"]);
    }

    #[test]
    fn detects_integer_one() {
        let sites = scan_source("1", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "1");
        assert_eq!(sites[0].kind, MutationKind::Numeric);
        assert_eq!(sites[0].replacements, vec!["0"]);
    }

    #[test]
    fn detects_integer_greater_than_one() {
        let sites = scan_source("42", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "42");
        assert_eq!(sites[0].kind, MutationKind::Numeric);
        assert_eq!(sites[0].replacements, vec!["0", "1", "-1"]);
    }

    #[test]
    fn detects_float_zero_point_zero() {
        let sites = scan_source("0.0", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "0.0");
        assert_eq!(sites[0].kind, MutationKind::Numeric);
        assert_eq!(sites[0].replacements, vec!["1.0"]);
    }

    #[test]
    fn detects_float_one_point_zero() {
        let sites = scan_source("1.0", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "1.0");
        assert_eq!(sites[0].kind, MutationKind::Numeric);
        assert_eq!(sites[0].replacements, vec!["0.0"]);
    }

    #[test]
    fn detects_float_general() {
        let sites = scan_source("3.14", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "3.14");
        assert_eq!(sites[0].replacements, vec!["0.0", "1.0", "-1.0"]);
    }

    #[test]
    fn detects_leading_dot_float() {
        let sites = scan_source(".5", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, ".5");
        assert_eq!(sites[0].kind, MutationKind::Numeric);
        assert_eq!(sites[0].replacements, vec!["0.0", "1.0", "-1.0"]);
    }

    #[test]
    fn detects_scientific_notation() {
        let sites = scan_source("1e-5", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "1e-5");
        assert_eq!(sites[0].kind, MutationKind::Numeric);
        // 1e-5 = 0.00001 (not 0 or 1), so default float replacements
        assert_eq!(sites[0].replacements, vec!["0.0", "1.0", "-1.0"]);
    }

    #[test]
    fn skips_numeric_inside_string() {
        let sites = scan_source("\"42\"", "test.R");
        assert!(sites.is_empty());
    }

    #[test]
    fn skips_numeric_inside_comment() {
        let sites = scan_source("# 42", "test.R");
        assert!(sites.is_empty());
    }

    #[test]
    fn skips_numeric_preceded_by_ident_char() {
        // The '0' in 'a0' is preceded by 'a' (ident char), so it's NOT a numeric literal
        let sites = scan_source("a0", "test.R");
        assert!(sites.is_empty());
    }

    #[test]
    fn skips_numeric_preceded_by_dot_ident() {
        // 'foo.5' — the '.' is preceded by 'o' (ident char), so NOT a numeric literal
        let sites = scan_source("foo.5", "test.R");
        assert!(sites.is_empty());
    }

    #[test]
    fn detects_numeric_after_assignment() {
        // 'a0 <- 0' — only the '0' after '<-' is a numeric literal
        let sites = scan_source("a0 <- 0", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "0");
        assert_eq!(sites[0].kind, MutationKind::Numeric);
    }

    #[test]
    fn rejects_r_integer_suffix() {
        // '1L' — 'L' is an ident char after the literal, so NOT a numeric site
        let sites = scan_source("1L", "test.R");
        assert!(sites.is_empty());
    }

    #[test]
    fn rejects_hex_prefix() {
        // '0x1F' — 'x' is an ident char after '0', so NOT a numeric site
        let sites = scan_source("0x1F", "test.R");
        assert!(sites.is_empty());
    }

    #[test]
    fn minus_five_has_two_sites() {
        // '"-5"' → '-' as Arithmetic, '5' as Numeric
        let sites = scan_source("-5", "test.R");
        assert_eq!(sites.len(), 2);
        assert_eq!(sites[0].original, "-");
        assert_eq!(sites[0].kind, MutationKind::Arithmetic);
        assert_eq!(sites[1].original, "5");
        assert_eq!(sites[1].kind, MutationKind::Numeric);
    }

    #[test]
    fn numeric_alongside_operators() {
        let sites = scan_source("x == 0", "test.R");
        assert_eq!(sites.len(), 2);
        assert_eq!(sites[0].original, "==");
        assert_eq!(sites[0].kind, MutationKind::Comparison);
        assert_eq!(sites[1].original, "0");
        assert_eq!(sites[1].kind, MutationKind::Numeric);
    }

    #[test]
    fn multiple_numeric_literals() {
        let sites = scan_source("1 + 2", "test.R");
        assert_eq!(sites.len(), 3);
        assert_eq!(sites[0].original, "1");
        assert_eq!(sites[0].kind, MutationKind::Numeric);
        assert_eq!(sites[0].replacements, vec!["0"]);
        assert_eq!(sites[1].original, "+");
        assert_eq!(sites[1].kind, MutationKind::Arithmetic);
        assert_eq!(sites[2].original, "2");
        assert_eq!(sites[2].kind, MutationKind::Numeric);
        assert_eq!(sites[2].replacements, vec!["0", "1", "-1"]);
    }

    #[test]
    fn zero_value_float_with_exponent() {
        // '0e5' has value 0.0 and is a float (has 'e')
        let sites = scan_source("0e5", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "0e5");
        assert_eq!(sites[0].kind, MutationKind::Numeric);
        assert_eq!(sites[0].replacements, vec!["1.0"]);
    }

    #[test]
    fn location_tracking_for_numeric() {
        let sites = scan_source(" 42", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].location.col, 2);
        assert_eq!(sites[0].location.span.start, 1);
        assert_eq!(sites[0].location.span.end, 3);
    }

    // ── find_matching_brace tests ──

    #[test]
    fn find_matching_brace_simple() {
        let bytes = b"{ }";
        assert_eq!(find_matching_brace(bytes, 0), Some(2));
    }

    #[test]
    fn find_matching_brace_nested() {
        let bytes = b"{ { } }";
        assert_eq!(find_matching_brace(bytes, 0), Some(6));
    }

    #[test]
    fn find_matching_brace_string() {
        let bytes = b"{ \"}\" }";
        assert_eq!(find_matching_brace(bytes, 0), Some(6));
    }

    #[test]
    fn find_matching_brace_comment() {
        let bytes = b"{ # }\n}";
        assert_eq!(find_matching_brace(bytes, 0), Some(6));
    }

    #[test]
    fn find_matching_brace_unclosed() {
        let bytes = b"{";
        assert_eq!(find_matching_brace(bytes, 0), None);
    }

    #[test]
    fn find_matching_brace_empty() {
        let bytes = b"{}";
        assert_eq!(find_matching_brace(bytes, 0), Some(1));
    }

    #[test]
    fn find_matching_brace_escaped_quote_in_string() {
        let bytes = br#"{ "\"" }"#;
        assert_eq!(find_matching_brace(bytes, 0), Some(7));
    }

    #[test]
    fn find_matching_brace_not_at_open_brace() {
        let bytes = b"x{ }";
        assert_eq!(find_matching_brace(bytes, 1), Some(3));
        assert_eq!(find_matching_brace(bytes, 0), None);
    }

    // ── Function body detection tests ──

    #[test]
    fn function_body_simple() {
        let sites = scan_source("f <- function(x) { x + 1 }", "test.R");
        let fn_sites: Vec<&MutationSite> = sites
            .iter()
            .filter(|s| matches!(s.kind, MutationKind::FunctionBody { .. }))
            .collect();
        assert_eq!(fn_sites.len(), 1);
        assert_eq!(fn_sites[0].original, "{ x + 1 }");
        assert_eq!(fn_sites[0].replacements, vec!["{ return(NULL) }"]);
        // "f <- function(x) { x + 1 }"
        //  0123456789...         ^---^
        // open_brace at 17, close_brace at 25
        assert_eq!(
            fn_sites[0].kind,
            MutationKind::FunctionBody {
                name: "f".to_string(),
                body_span: Span { start: 17, end: 26 },
            }
        );
        assert_eq!(fn_sites[0].location.span.start, 17);
        assert_eq!(fn_sites[0].location.span.end, 26);
    }

    #[test]
    fn function_body_nested_braces() {
        let sites = scan_source("f <- function() { if(x) { 1 } else { 2 } }", "test.R");
        // FunctionBody + internal numerics `1` and `2`
        assert_eq!(sites.len(), 3);
        // Body span covers outer braces: " { if(x) { 1 } else { 2 } }"
        assert_eq!(sites[0].original, "{ if(x) { 1 } else { 2 } }");
        assert_eq!(sites[0].replacements, vec!["{ return(NULL) }"]);
        assert!(matches!(sites[0].kind, MutationKind::FunctionBody { .. }));
        assert_eq!(sites[1].original, "1");
        assert_eq!(sites[1].kind, MutationKind::Numeric);
        assert_eq!(sites[2].original, "2");
        assert_eq!(sites[2].kind, MutationKind::Numeric);
    }

    #[test]
    fn function_body_string_with_brace() {
        let sites = scan_source("f <- function() { x <- \"}\" }", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "{ x <- \"}\" }");
        assert_eq!(sites[0].replacements, vec!["{ return(NULL) }"]);
    }

    #[test]
    fn function_body_noop_skip() {
        let sites = scan_source("f <- function() { return(NULL) }", "test.R");
        assert_eq!(sites.len(), 0);
    }

    #[test]
    fn function_body_name_new_skip() {
        let sites = scan_source("new <- function() { 1 }", "test.R");
        // No FunctionBody sites (name "new" is skipped), but numeric `1` may appear
        let fn_sites: Vec<&MutationSite> = sites
            .iter()
            .filter(|s| matches!(s.kind, MutationKind::FunctionBody { .. }))
            .collect();
        assert_eq!(fn_sites.len(), 0);
    }

    #[test]
    fn function_body_anonymous_skip() {
        let sites = scan_source("function() { 1 }", "test.R");
        // No FunctionBody sites (anonymous — no name), but numeric `1` may appear
        let fn_sites: Vec<&MutationSite> = sites
            .iter()
            .filter(|s| matches!(s.kind, MutationKind::FunctionBody { .. }))
            .collect();
        assert_eq!(fn_sites.len(), 0);
    }

    #[test]
    fn function_body_single_expression_skip() {
        let sites = scan_source("f <- function(x) x", "test.R");
        assert_eq!(sites.len(), 0);
    }

    #[test]
    fn function_body_unclosed_skip() {
        let sites = scan_source("f <- function() {", "test.R");
        assert_eq!(sites.len(), 0);
    }

    #[test]
    fn function_body_multiple_functions() {
        let sites = scan_source(
            "f <- function(x) { x + 1 }\ng <- function(y) { y - 1 }",
            "test.R",
        );
        // Two function bodies plus internal operators/numerics
        let fn_sites: Vec<&MutationSite> = sites
            .iter()
            .filter(|s| matches!(s.kind, MutationKind::FunctionBody { .. }))
            .collect();
        assert_eq!(fn_sites.len(), 2);
        assert_eq!(fn_sites[0].original, "{ x + 1 }");
        assert_eq!(fn_sites[1].original, "{ y - 1 }");
        // Internal sites detected alongside function bodies
        assert!(sites.iter().any(|s| s.original == "+"));
        assert!(sites.iter().any(|s| s.original == "-"));
    }

    #[test]
    fn function_body_with_default_arg_braces() {
        // Default arg has {1} which should NOT be confused with function body
        let sites = scan_source("f <- function(x = {1}) { x }", "test.R");
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "{ x }");
    }

    #[test]
    fn function_body_comment_inside_body() {
        let sites = scan_source("f <- function() { # comment\n  x + 1\n}", "test.R");
        // FunctionBody + `+` arithmetic + `1` numeric
        assert_eq!(sites.len(), 3);
        assert!(matches!(sites[0].kind, MutationKind::FunctionBody { .. }));
        assert!(sites[0].original.contains("x + 1"));
        assert_eq!(sites[0].replacements, vec!["{ return(NULL) }"]);
        assert!(sites.iter().any(|s| s.original == "+"));
        assert!(sites.iter().any(|s| s.original == "1"));
    }
}
