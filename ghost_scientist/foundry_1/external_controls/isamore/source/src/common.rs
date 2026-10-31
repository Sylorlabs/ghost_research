use std::str::FromStr;

use colored::Colorize;
use std::io::Write;

const MAX_POS_LEN: usize = 50;
const MAX_TIME_LEN: usize = 10;

#[allow(dead_code)]
pub fn setup_logger_with_level(level: impl AsRef<str>) {
  let rust_log = level.as_ref().to_string();

  // if logger has not been set, set logger
  match env_logger::Builder::new()
    .format(|buf, record| {
      let mut pos = format!(
        "{}:{}",
        record.file().unwrap_or("unknown"),
        record.line().unwrap_or(0)
      );
      pos.truncate(MAX_POS_LEN);
      let pos_padding = " ".repeat(MAX_POS_LEN - pos.len());
      let mut time = format!("{}", chrono::Local::now().format("%H:%M:%S"));
      time.truncate(MAX_TIME_LEN);
      let time_padding = " ".repeat(MAX_TIME_LEN - time.len());

      writeln!(
        buf,
        "{}{}{}{}[{}] - {}",
        pos,
        pos_padding,
        time,
        time_padding,
        {
          let level = record.level();
          let color = match level {
            log::Level::Error => colored::Color::Red,
            log::Level::Warn => colored::Color::Yellow,
            log::Level::Info => colored::Color::Green,
            log::Level::Debug => colored::Color::Blue,
            log::Level::Trace => colored::Color::Magenta,
          };
          let mut level_str = level.to_string();
          // fill level_str to 5 chars
          if level_str.len() < 5 {
            level_str =
              format!("{}{}", " ".repeat(5 - level_str.len()), level_str);
          }
          format!("{}", level_str.color(color))
        },
        record.args()
      )
    })
    .filter_level(log::LevelFilter::from_str(&rust_log).unwrap())
    .try_init()
  {
    Ok(_) => {
      log::debug!("Logger is set");
    }
    Err(_e) => {
      log::debug!("Logger has been set");
    }
  }

  // set RUST_BACKTRACE
  unsafe { std::env::set_var("RUST_BACKTRACE", "1") };
}
