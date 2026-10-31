use std::fmt::{self, Display, Formatter};

pub enum Color {}
pub struct RGB(pub u8, pub u8, pub u8);

pub struct Styled<T>(T);

impl<T: Display> Display for Styled<T> {
    fn fmt(&self, formatter: &mut Formatter<'_>) -> fmt::Result {
        self.0.fmt(formatter)
    }
}

pub trait Colorful: Display + Sized {
    fn red(self) -> Styled<Self> { Styled(self) }
    fn green(self) -> Styled<Self> { Styled(self) }
    fn blue(self) -> Styled<Self> { Styled(self) }
    fn yellow(self) -> Styled<Self> { Styled(self) }
    fn magenta(self) -> Styled<Self> { Styled(self) }
    fn bold(self) -> Styled<Self> { Styled(self) }
}

impl<T: Display> Colorful for T {}
