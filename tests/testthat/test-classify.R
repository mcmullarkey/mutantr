test_that("mutant_classify_outcome returns lowercase strings for all 4 outcomes", {
  # The R wrapper calls Rust classify(source_error, passed, timeout, error)
  # Precedence: timeout > source_error > error || !passed > missed
  expect_equal(mutant_classify_outcome(TRUE, FALSE, FALSE, FALSE), "timeout")
  expect_equal(mutant_classify_outcome(FALSE, TRUE, FALSE, FALSE), "unviable")
  expect_equal(mutant_classify_outcome(FALSE, FALSE, TRUE, FALSE), "caught")
  expect_equal(mutant_classify_outcome(FALSE, FALSE, FALSE, TRUE), "missed")
  expect_equal(mutant_classify_outcome(FALSE, FALSE, FALSE, FALSE), "caught")
})
