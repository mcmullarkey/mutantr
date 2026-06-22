#[test]
fn scan_finds_equality_operator_and_boolean() {
    let source = "if (x == y) TRUE";
    let sites = rmutant::mutant::scan_source(source, "test.R");
    assert_eq!(sites.len(), 2); // == and TRUE
    assert_eq!(sites[0].original, "==");
    assert_eq!(sites[0].replacements, vec!["!="]);
    assert_eq!(sites[1].original, "TRUE");
    assert_eq!(sites[1].replacements, vec!["FALSE"]);
}

#[test]
fn scan_skips_assignment_operators() {
    let sites = rmutant::mutant::scan_source("x <- y\nz <<- w", "test.R");
    assert!(sites.is_empty());
}

#[test]
fn scan_skips_strings_and_comments() {
    let source = "x == y # not == this\n\"also == not this\"\nz != w";
    let sites = rmutant::mutant::scan_source(source, "test.R");
    assert_eq!(sites.len(), 2);
    assert_eq!(sites[0].original, "==");
    assert_eq!(sites[0].location.line, 1);
    assert_eq!(sites[1].original, "!=");
    assert_eq!(sites[1].location.line, 3);
}

#[test]
fn scan_respects_word_boundaries() {
    let source = "isTRUE(x)\nTRUE";
    let sites = rmutant::mutant::scan_source(source, "test.R");
    assert_eq!(sites.len(), 1);
    assert_eq!(sites[0].original, "TRUE");
    assert_eq!(sites[0].location.line, 2);
}

#[test]
fn scan_realistic_r_function() {
    let source = r#"check_value <- function(x, threshold = 10) {
  if (is.numeric(x) && x >= threshold) {
    return(TRUE)
  } else if (x == 0 || x < -1) {
    return(FALSE)
  }
  x + 1
}"#;
    let sites = rmutant::mutant::scan_source(source, "check.R");
    // FunctionBody site detected alongside internal operators/numerics/booleans
    let fn_sites: Vec<&rmutant::mutant::types::MutationSite> = sites
        .iter()
        .filter(|s| {
            matches!(
                s.kind,
                rmutant::mutant::types::MutationKind::FunctionBody { .. }
            )
        })
        .collect();
    assert_eq!(fn_sites.len(), 1);
    assert!(fn_sites[0].original.starts_with('{'));
    assert!(fn_sites[0].original.ends_with('}'));
    assert_eq!(fn_sites[0].replacements, vec!["{ return(NULL) }"]);
    // Should NOT contain <- (assignment)
    let originals: Vec<&str> = sites.iter().map(|s| s.original.as_str()).collect();
    assert!(!originals.contains(&"<-"));
    // Internal operators/numerics/booleans are detected alongside FunctionBody
    assert!(
        sites.iter().any(|s| s.original == "&&"),
        "expected && operator inside body"
    );
    assert!(
        sites.iter().any(|s| s.original == "=="),
        "expected == operator inside body"
    );
    assert!(
        sites.iter().any(|s| s.original == "+"),
        "expected + operator inside body"
    );
    assert!(
        sites.iter().any(|s| s.original == "TRUE"),
        "expected TRUE boolean inside body"
    );
    assert!(
        sites.iter().any(|s| s.original == "FALSE"),
        "expected FALSE boolean inside body"
    );
}

#[test]
fn scan_then_mutate_round_trip() {
    let source = "if (x == y) TRUE";
    let sites = rmutant::mutant::scan_source(source, "test.R");

    // Mutate == to !=
    let mutation = rmutant::mutant::types::Mutation {
        site: sites[0].clone(),
        replacement: "!=".to_string(),
    };
    let result = rmutant::mutant::apply_mutation(source, &mutation).unwrap();
    assert_eq!(result.text, "if (x != y) TRUE");

    // Mutate TRUE to FALSE
    let mutation2 = rmutant::mutant::types::Mutation {
        site: sites[1].clone(),
        replacement: "FALSE".to_string(),
    };
    let result2 = rmutant::mutant::apply_mutation(source, &mutation2).unwrap();
    assert_eq!(result2.text, "if (x == y) FALSE");
}

#[test]
fn mutate_length_changing_replacement() {
    let source = "x <= y";
    let sites = rmutant::mutant::scan_source(source, "test.R");
    let mutation = rmutant::mutant::types::Mutation {
        site: sites[0].clone(),
        replacement: ">".to_string(),
    };
    let result = rmutant::mutant::apply_mutation(source, &mutation).unwrap();
    assert_eq!(result.text, "x > y");
}

#[test]
fn scan_package_finds_sites_in_r_directory() {
    let dir = tempfile::tempdir().unwrap();
    let r_dir = dir.path().join("R");
    std::fs::create_dir(&r_dir).unwrap();
    std::fs::write(r_dir.join("utils.R"), "x == y").unwrap();
    std::fs::write(r_dir.join("helpers.R"), "a + b").unwrap();

    let sites = rmutant::mutant::scan_package(dir.path().to_str().unwrap()).unwrap();
    assert_eq!(sites.len(), 2);
    let originals: Vec<&str> = sites.iter().map(|s| s.original.as_str()).collect();
    assert!(originals.contains(&"=="));
    assert!(originals.contains(&"+"));
}

#[test]
fn scan_file_works() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("test.R");
    std::fs::write(&path, "TRUE && FALSE").unwrap();

    let sites = rmutant::mutant::scan_file(path.to_str().unwrap()).unwrap();
    assert_eq!(sites.len(), 3); // TRUE, &&, FALSE
}

#[test]
fn scan_file_json_returns_parseable_json() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("test.R");
    std::fs::write(&path, "x + y").unwrap();

    let json = rmutant::mutant::scan_file_json(path.to_str().unwrap()).unwrap();
    let parsed: Vec<rmutant::mutant::types::MutationSite> = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed.len(), 1);
    assert_eq!(parsed[0].original, "+");
}

#[test]
fn scan_package_json_returns_parseable_json() {
    let dir = tempfile::tempdir().unwrap();
    let r_dir = dir.path().join("R");
    std::fs::create_dir(&r_dir).unwrap();
    std::fs::write(r_dir.join("utils.R"), "TRUE").unwrap();

    let json = rmutant::mutant::scan_package_json(dir.path().to_str().unwrap()).unwrap();
    let parsed: Vec<rmutant::mutant::types::MutationSite> = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed.len(), 1);
    assert_eq!(parsed[0].original, "TRUE");
}

#[test]
fn prepare_all_returns_mutated_content_for_package() {
    let dir = tempfile::tempdir().unwrap();
    let r_dir = dir.path().join("R");
    std::fs::create_dir(&r_dir).unwrap();
    std::fs::write(r_dir.join("math.R"), "x == y").unwrap();

    let prepared = rmutant::mutant::prepare_all(dir.path().to_str().unwrap()).unwrap();
    assert_eq!(prepared.len(), 1);
    assert_eq!(prepared[0].original, "==");
    assert_eq!(prepared[0].replacement, "!=");
    assert_eq!(prepared[0].mutated_content, "x != y");
    assert_eq!(prepared[0].file, "math.R");
    assert_eq!(prepared[0].line, 1);
}

#[test]
fn scan_finds_numeric_literals() {
    let source = "x == 0";
    let sites = rmutant::mutant::scan_source(source, "test.R");
    assert_eq!(sites.len(), 2);
    assert_eq!(sites[0].original, "==");
    assert_eq!(sites[1].original, "0");
    assert_eq!(sites[1].kind, rmutant::mutant::types::MutationKind::Numeric);
    assert_eq!(sites[1].replacements, vec!["1"]);
}

#[test]
fn scan_numeric_round_trip() {
    let source = "if (x == 1) TRUE";
    let sites = rmutant::mutant::scan_source(source, "test.R");
    // Find the Numeric site for '1'
    let num_site = sites
        .iter()
        .find(|s| s.kind == rmutant::mutant::types::MutationKind::Numeric)
        .unwrap();
    assert_eq!(num_site.original, "1");
    assert_eq!(num_site.replacements, vec!["0"]);

    // Mutate 1 to 0
    let mutation = rmutant::mutant::types::Mutation {
        site: num_site.clone(),
        replacement: "0".to_string(),
    };
    let result = rmutant::mutant::apply_mutation(source, &mutation).unwrap();
    assert_eq!(result.text, "if (x == 0) TRUE");
}

#[test]
fn scan_numeric_json_round_trip() {
    let source = "x <- 42";
    let sites = rmutant::mutant::scan_source(source, "test.R");
    let json = serde_json::to_string(&sites).unwrap();
    let parsed: Vec<rmutant::mutant::types::MutationSite> = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed.len(), 1);
    assert_eq!(parsed[0].original, "42");
    assert_eq!(
        parsed[0].kind,
        rmutant::mutant::types::MutationKind::Numeric
    );
}

#[test]
fn scan_numeric_in_realistic_r_function() {
    let source = r#"compute <- function(x, factor = 1.5) {
  result <- x * factor
  if (result > 100) {
    return(0)
  }
  result / 2
}"#;
    let sites = rmutant::mutant::scan_source(source, "compute.R");
    // FunctionBody site detected alongside internal operators/numerics
    let fn_sites: Vec<&rmutant::mutant::types::MutationSite> = sites
        .iter()
        .filter(|s| {
            matches!(
                s.kind,
                rmutant::mutant::types::MutationKind::FunctionBody { .. }
            )
        })
        .collect();
    assert_eq!(fn_sites.len(), 1);
    assert!(fn_sites[0].original.starts_with('{'));
    assert!(fn_sites[0].original.ends_with('}'));
    assert_eq!(fn_sites[0].replacements, vec!["{ return(NULL) }"]);
    // Numeric literals inside function body are still detected
    // (1.5 is in the parameter list, consumed by function detection, not a regression)
    assert!(
        sites.iter().any(|s| s.original == "100"),
        "expected 100 numeric inside body"
    );
    assert!(
        sites.iter().any(|s| s.original == "0"),
        "expected 0 numeric inside body"
    );
    assert!(
        sites.iter().any(|s| s.original == "2"),
        "expected 2 numeric inside body"
    );
    // Operators inside body also detected
    assert!(
        sites.iter().any(|s| s.original == "*"),
        "expected * operator inside body"
    );
    assert!(
        sites.iter().any(|s| s.original == ">"),
        "expected > operator inside body"
    );
    assert!(
        sites.iter().any(|s| s.original == "/"),
        "expected / operator inside body"
    );
}

#[test]
fn prepare_all_handles_multiple_files_and_mutations() {
    let dir = tempfile::tempdir().unwrap();
    let r_dir = dir.path().join("R");
    std::fs::create_dir(&r_dir).unwrap();
    std::fs::write(r_dir.join("a.R"), "x > y").unwrap();
    std::fs::write(r_dir.join("b.R"), "TRUE").unwrap();

    let prepared = rmutant::mutant::prepare_all(dir.path().to_str().unwrap()).unwrap();
    assert_eq!(prepared.len(), 2); // > -> <= and TRUE -> FALSE
    let originals: Vec<&str> = prepared.iter().map(|p| p.original.as_str()).collect();
    assert!(originals.contains(&">"));
    assert!(originals.contains(&"TRUE"));
}

// ── Function body mutation tests ──

#[test]
fn function_body_simple_integration() {
    let source = "f <- function(x) { x + 1 }";
    let sites = rmutant::mutant::scan_source(source, "test.R");
    let fn_sites: Vec<&rmutant::mutant::types::MutationSite> = sites
        .iter()
        .filter(|s| {
            matches!(
                s.kind,
                rmutant::mutant::types::MutationKind::FunctionBody { .. }
            )
        })
        .collect();
    assert_eq!(fn_sites.len(), 1);
    assert_eq!(fn_sites[0].original, "{ x + 1 }");
    assert_eq!(fn_sites[0].replacements, vec!["{ return(NULL) }"]);

    // Apply the mutation
    let mutation = rmutant::mutant::types::Mutation {
        site: fn_sites[0].clone(),
        replacement: "{ return(NULL) }".to_string(),
    };
    let result = rmutant::mutant::apply_mutation(source, &mutation).unwrap();
    assert_eq!(result.text, "f <- function(x) { return(NULL) }");
}

#[test]
fn function_body_nested_braces_integration() {
    let source = "f <- function() { if(x) { 1 } else { 2 } }";
    let sites = rmutant::mutant::scan_source(source, "test.R");
    // FunctionBody + internal numerics `1` and `2`
    assert_eq!(sites.len(), 3);
    assert!(matches!(
        sites[0].kind,
        rmutant::mutant::types::MutationKind::FunctionBody { .. }
    ));
    assert_eq!(sites[0].original, "{ if(x) { 1 } else { 2 } }");

    let mutation = rmutant::mutant::types::Mutation {
        site: sites[0].clone(),
        replacement: sites[0].replacements[0].clone(),
    };
    let result = rmutant::mutant::apply_mutation(source, &mutation).unwrap();
    assert_eq!(result.text, "f <- function() { return(NULL) }");
}

#[test]
fn function_body_string_with_brace_integration() {
    let source = "f <- function() { x <- \"}\" }";
    let sites = rmutant::mutant::scan_source(source, "test.R");
    assert_eq!(sites.len(), 1);
    assert_eq!(sites[0].original, "{ x <- \"}\" }");

    let mutation = rmutant::mutant::types::Mutation {
        site: sites[0].clone(),
        replacement: sites[0].replacements[0].clone(),
    };
    let result = rmutant::mutant::apply_mutation(source, &mutation).unwrap();
    assert_eq!(result.text, "f <- function() { return(NULL) }");
}

#[test]
fn function_body_noop_skip_integration() {
    let source = "f <- function() { return(NULL) }";
    let sites = rmutant::mutant::scan_source(source, "test.R");
    assert_eq!(sites.len(), 0);
}

#[test]
fn function_body_name_new_skip_integration() {
    let source = "new <- function() { 1 }";
    let sites = rmutant::mutant::scan_source(source, "test.R");
    // No FunctionBody sites (name "new" skipped), but numeric `1` may appear
    let fn_sites: Vec<&rmutant::mutant::types::MutationSite> = sites
        .iter()
        .filter(|s| {
            matches!(
                s.kind,
                rmutant::mutant::types::MutationKind::FunctionBody { .. }
            )
        })
        .collect();
    assert_eq!(fn_sites.len(), 0);
}

#[test]
fn function_body_anonymous_skip_integration() {
    let source = "function() { 1 }";
    let sites = rmutant::mutant::scan_source(source, "test.R");
    // No FunctionBody sites (anonymous — no name), but numeric `1` may appear
    let fn_sites: Vec<&rmutant::mutant::types::MutationSite> = sites
        .iter()
        .filter(|s| {
            matches!(
                s.kind,
                rmutant::mutant::types::MutationKind::FunctionBody { .. }
            )
        })
        .collect();
    assert_eq!(fn_sites.len(), 0);
}

#[test]
fn function_body_single_expression_skip_integration() {
    let source = "f <- function(x) x";
    let sites = rmutant::mutant::scan_source(source, "test.R");
    assert_eq!(sites.len(), 0);
}

#[test]
fn function_body_unclosed_skip_integration() {
    let source = "f <- function() {";
    let sites = rmutant::mutant::scan_source(source, "test.R");
    assert_eq!(sites.len(), 0);
}

#[test]
fn function_body_multiple_functions_integration() {
    let source = "f <- function(x) { x + 1 }\ng <- function(y) { y - 1 }";
    let sites = rmutant::mutant::scan_source(source, "test.R");
    let fn_sites: Vec<&rmutant::mutant::types::MutationSite> = sites
        .iter()
        .filter(|s| {
            matches!(
                s.kind,
                rmutant::mutant::types::MutationKind::FunctionBody { .. }
            )
        })
        .collect();
    assert_eq!(fn_sites.len(), 2);
    assert_eq!(fn_sites[0].original, "{ x + 1 }");
    assert_eq!(fn_sites[1].original, "{ y - 1 }");
}

#[test]
fn function_body_json_round_trip() {
    let source = "f <- function(x) { x + 1 }";
    let sites = rmutant::mutant::scan_source(source, "test.R");
    let json = serde_json::to_string(&sites).unwrap();
    let parsed: Vec<rmutant::mutant::types::MutationSite> = serde_json::from_str(&json).unwrap();
    // All sites survived JSON round-trip
    let fn_sites: Vec<&rmutant::mutant::types::MutationSite> = parsed
        .iter()
        .filter(|s| {
            matches!(
                s.kind,
                rmutant::mutant::types::MutationKind::FunctionBody { .. }
            )
        })
        .collect();
    assert_eq!(fn_sites.len(), 1);
    assert_eq!(fn_sites[0].original, "{ x + 1 }");
    assert_eq!(fn_sites[0].replacements, vec!["{ return(NULL) }"]);
    assert!(matches!(
        fn_sites[0].kind,
        rmutant::mutant::types::MutationKind::FunctionBody { .. }
    ));
    // Internal sites also survived round-trip
    assert!(parsed.iter().any(|s| s.original == "+"));
    assert!(parsed.iter().any(|s| s.original == "1"));
}

#[test]
fn function_body_with_numeric_operators_mixed() {
    // A function with both body mutation and internal operators
    let source = "f <- function(x) { x + 1 }";
    let sites = rmutant::mutant::scan_source(source, "test.R");
    // Should have: function body mutation + `+` operator + `1` numeric
    let fn_bodies: Vec<&rmutant::mutant::types::MutationSite> = sites
        .iter()
        .filter(|s| {
            matches!(
                s.kind,
                rmutant::mutant::types::MutationKind::FunctionBody { .. }
            )
        })
        .collect();
    assert_eq!(fn_bodies.len(), 1);
    assert_eq!(fn_bodies[0].original, "{ x + 1 }");
    // Internal sites detected alongside FunctionBody
    assert!(
        sites.iter().any(|s| s.original == "+"),
        "expected + operator inside body"
    );
    assert!(
        sites.iter().any(|s| s.original == "1"),
        "expected 1 numeric inside body"
    );
    assert!(sites
        .iter()
        .any(|s| s.kind == rmutant::mutant::types::MutationKind::Arithmetic));
    assert!(sites
        .iter()
        .any(|s| s.kind == rmutant::mutant::types::MutationKind::Numeric));
}

#[test]
fn function_body_realistic_r_file() {
    let source = r#"compute <- function(x, factor = 1.5) {
  result <- x * factor
  if (result > 100) {
    return(0)
  }
  result / 2
}"#;
    let sites = rmutant::mutant::scan_source(source, "compute.R");
    // Should find: function body (the entire function body), plus numeric literals inside
    let fn_bodies: Vec<&rmutant::mutant::types::MutationSite> = sites
        .iter()
        .filter(|s| {
            matches!(
                s.kind,
                rmutant::mutant::types::MutationKind::FunctionBody { .. }
            )
        })
        .collect();
    assert_eq!(fn_bodies.len(), 1);
    // The body should span from the opening { to the closing }
    assert!(fn_bodies[0].original.starts_with('{'));
    assert!(fn_bodies[0].original.ends_with('}'));
    assert_eq!(fn_bodies[0].replacements, vec!["{ return(NULL) }"]);

    // Apply the body mutation
    let mutation = rmutant::mutant::types::Mutation {
        site: fn_bodies[0].clone(),
        replacement: "{ return(NULL) }".to_string(),
    };
    let result = rmutant::mutant::apply_mutation(source, &mutation).unwrap();
    assert!(result.text.contains("{ return(NULL) }"));
    // Original body should be gone
    assert!(!result.text.contains("result <- x * factor"));
}
