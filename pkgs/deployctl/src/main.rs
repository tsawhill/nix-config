use std::process::ExitCode;

fn main() -> ExitCode {
    match deployctl::run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("error: {error:#}");
            ExitCode::FAILURE
        }
    }
}
