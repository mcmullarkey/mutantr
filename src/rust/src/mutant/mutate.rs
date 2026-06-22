use super::error::MutantError;
use super::types::{MutatedSource, Mutation};

/// Apply a mutation to source text, returning the mutated source.
pub fn apply_mutation(source: &str, mutation: &Mutation) -> Result<MutatedSource, MutantError> {
    let span = &mutation.site.location.span;

    if span.end > source.len() {
        return Err(MutantError::OutOfBounds {
            offset: span.end,
            file_len: source.len(),
        });
    }

    let mut result =
        String::with_capacity(source.len() - (span.end - span.start) + mutation.replacement.len());
    result.push_str(&source[..span.start]);
    result.push_str(&mutation.replacement);
    result.push_str(&source[span.end..]);

    Ok(MutatedSource {
        file: mutation.site.location.file.clone(),
        mutation: mutation.clone(),
        text: result,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::types::{Location, MutationKind, MutationSite, Span};

    fn make_mutation(start: usize, end: usize, original: &str, replacement: &str) -> Mutation {
        Mutation {
            site: MutationSite {
                location: Location {
                    file: "test.R".to_string(),
                    line: 1,
                    col: start + 1,
                    span: Span { start, end },
                },
                original: original.to_string(),
                kind: MutationKind::Comparison,
                replacements: vec![replacement.to_string()],
            },
            replacement: replacement.to_string(),
        }
    }

    #[test]
    fn simple_replacement() {
        let m = make_mutation(2, 4, "==", "!=");
        let result = apply_mutation("x == y", &m).unwrap();
        assert_eq!(result.text, "x != y");
    }

    #[test]
    fn length_changing_replacement() {
        let m = make_mutation(2, 4, "<=", ">");
        let result = apply_mutation("x <= y", &m).unwrap();
        assert_eq!(result.text, "x > y");
    }

    #[test]
    fn replacement_at_start() {
        let m = make_mutation(0, 4, "TRUE", "FALSE");
        let result = apply_mutation("TRUE", &m).unwrap();
        assert_eq!(result.text, "FALSE");
    }

    #[test]
    fn replacement_at_end() {
        let m = make_mutation(4, 8, "TRUE", "FALSE");
        let result = apply_mutation("x = TRUE", &m).unwrap();
        assert_eq!(result.text, "x = FALSE");
    }

    #[test]
    fn out_of_bounds_returns_error() {
        let m = make_mutation(0, 100, "==", "!=");
        let result = apply_mutation("x == y", &m);
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            MutantError::OutOfBounds { .. }
        ));
    }

    #[test]
    fn preserves_surrounding_text() {
        let m = make_mutation(2, 4, "==", "!=");
        let result = apply_mutation("a == b == c", &m).unwrap();
        assert_eq!(result.text, "a != b == c");
    }

    #[test]
    fn file_name_preserved_in_result() {
        let m = make_mutation(2, 4, "==", "!=");
        let result = apply_mutation("x == y", &m).unwrap();
        assert_eq!(result.file, "test.R");
    }

    #[test]
    fn mutation_preserved_in_result() {
        let m = make_mutation(2, 4, "==", "!=");
        let result = apply_mutation("x == y", &m).unwrap();
        assert_eq!(result.mutation.replacement, "!=");
    }
}
