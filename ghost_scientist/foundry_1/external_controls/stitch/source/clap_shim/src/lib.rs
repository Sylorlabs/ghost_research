pub use clap_derive::{ArgEnum, Parser};

pub trait Parser: Sized {
    fn parse_from<I, T>(args: I) -> Self
    where
        I: IntoIterator<Item = T>,
        T: Into<std::ffi::OsString> + Clone;
}

pub trait ArgEnum {}

pub fn parse_default<T: std::str::FromStr>(value: &str) -> T
where
    T::Err: std::fmt::Debug,
{
    value.parse().expect("invalid pinned Clap default")
}

#[macro_export]
macro_rules! value_parser {
    ($ty:ty) => {
        ()
    };
}
