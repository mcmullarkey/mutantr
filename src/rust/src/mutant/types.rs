use serde::{Deserialize, Serialize};

/// Byte offset range within source text.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Span {
    pub start: usize,
    pub end: usize,
}

/// Location of a token in source.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Location {
    pub file: String,
    pub line: usize,
    pub col: usize,
    pub span: Span,
}

/// Category of mutation operator.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum MutationKind {
    Boolean,
    Comparison,
    Arithmetic,
    Logical,
    Numeric,
    /// Replace the body of a named function with `{ return(NULL) }`.
    FunctionBody {
        name: String,
        body_span: Span,
    },
}

/// A site in source code where a mutation can be applied.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MutationSite {
    pub location: Location,
    pub original: String,
    pub kind: MutationKind,
    pub replacements: Vec<String>,
}

/// A specific mutation to apply: one site, one chosen replacement.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Mutation {
    pub site: MutationSite,
    pub replacement: String,
}

/// The result of applying a mutation to source text.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MutatedSource {
    pub file: String,
    pub mutation: Mutation,
    pub text: String,
}

/// Outcome of running tests against a mutant.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum Outcome {
    Caught,
    Missed,
    Unviable,
    Timeout,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mutation_site_can_be_constructed() {
        let site = MutationSite {
            location: Location {
                file: "test.R".to_string(),
                line: 1,
                col: 5,
                span: Span { start: 4, end: 6 },
            },
            original: "==".to_string(),
            kind: MutationKind::Comparison,
            replacements: vec!["!=".to_string()],
        };
        assert_eq!(site.original, "==");
        assert_eq!(site.replacements, vec!["!="]);
        assert_eq!(site.location.line, 1);
    }
}
