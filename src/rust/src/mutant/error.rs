use std::path::PathBuf;

#[derive(Debug, thiserror::Error)]
pub enum MutantError {
    #[error("file not found: {0}")]
    FileNotFound(PathBuf),

    #[error("could not read {path}: {source}")]
    ReadError {
        path: PathBuf,
        source: std::io::Error,
    },

    #[error("mutation span out of bounds: offset {offset} exceeds file length {file_len}")]
    OutOfBounds { offset: usize, file_len: usize },
}
