use super::types::MutationKind;

/// A pair defining one mutation: replace `from` with `to`.
#[derive(Debug, Clone)]
pub struct OperatorPair {
    pub from: &'static str,
    pub to: &'static str,
    pub kind: MutationKind,
}

/// Returns all mutation operator pairs, sorted by descending `from` length.
/// This ensures multi-character operators (e.g. `<=`) match before their
/// single-character prefixes (e.g. `<`).
pub fn all_operators() -> Vec<OperatorPair> {
    use MutationKind::*;

    let mut ops = vec![
        OperatorPair {
            from: "TRUE",
            to: "FALSE",
            kind: Boolean,
        },
        OperatorPair {
            from: "FALSE",
            to: "TRUE",
            kind: Boolean,
        },
        OperatorPair {
            from: "==",
            to: "!=",
            kind: Comparison,
        },
        OperatorPair {
            from: "!=",
            to: "==",
            kind: Comparison,
        },
        OperatorPair {
            from: "<=",
            to: ">",
            kind: Comparison,
        },
        OperatorPair {
            from: ">=",
            to: "<",
            kind: Comparison,
        },
        OperatorPair {
            from: "<",
            to: ">=",
            kind: Comparison,
        },
        OperatorPair {
            from: ">",
            to: "<=",
            kind: Comparison,
        },
        OperatorPair {
            from: "+",
            to: "-",
            kind: Arithmetic,
        },
        OperatorPair {
            from: "-",
            to: "+",
            kind: Arithmetic,
        },
        OperatorPair {
            from: "*",
            to: "/",
            kind: Arithmetic,
        },
        OperatorPair {
            from: "/",
            to: "*",
            kind: Arithmetic,
        },
        OperatorPair {
            from: "&&",
            to: "||",
            kind: Logical,
        },
        OperatorPair {
            from: "||",
            to: "&&",
            kind: Logical,
        },
        OperatorPair {
            from: "&",
            to: "|",
            kind: Logical,
        },
        OperatorPair {
            from: "|",
            to: "&",
            kind: Logical,
        },
    ];

    ops.sort_by(|a, b| b.from.len().cmp(&a.from.len()));
    ops
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn registry_is_not_empty() {
        assert!(!all_operators().is_empty());
    }

    #[test]
    fn multi_char_operators_come_before_single_char() {
        let ops = all_operators();
        let le_pos = ops.iter().position(|o| o.from == "<=").unwrap();
        let lt_pos = ops.iter().position(|o| o.from == "<").unwrap();
        assert!(le_pos < lt_pos, "<= must appear before <");

        let and2_pos = ops.iter().position(|o| o.from == "&&").unwrap();
        let and1_pos = ops.iter().position(|o| o.from == "&").unwrap();
        assert!(and2_pos < and1_pos, "&& must appear before &");

        let or2_pos = ops.iter().position(|o| o.from == "||").unwrap();
        let or1_pos = ops.iter().position(|o| o.from == "|").unwrap();
        assert!(or2_pos < or1_pos, "|| must appear before |");
    }

    #[test]
    fn every_from_has_a_pairing() {
        let ops = all_operators();
        for op in &ops {
            let has_reverse = ops.iter().any(|o| o.from == op.to);
            assert!(
                has_reverse,
                "operator '{}' -> '{}' has no reverse pairing",
                op.from, op.to
            );
        }
    }
}
